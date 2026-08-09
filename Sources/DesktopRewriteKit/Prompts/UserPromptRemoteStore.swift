import Foundation

/// Reads (and writes) the shared `user_prompts` table.
///
/// This is the one table both surfaces own read-write (§2) — it is what makes a
/// user's buttons follow them from phone to laptop. Its schema is a contract owned
/// by the iOS repo; changing it is a two-repo change.
///
/// Everything else desktop touches goes to the `desktop` schema. Nothing here reads
/// or writes `ai_rewrite_events` or `ai_rewrite_usage_buckets`.
public struct UserPromptRemoteStore: Sendable {

    private let config: SupabaseConfig
    private let auth: AuthService
    private let session: URLSession

    public init(config: SupabaseConfig, auth: AuthService, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    public func fetch() async throws -> [UserPrompt] {
        var components = URLComponents(
            url: config.restEndpoint.appendingPathComponent("user_prompts"),
            resolvingAgainstBaseURL: false
        )!
        // RLS scopes this to the caller's rows, so no explicit user_id filter is
        // needed — and adding one would be a lie about where the boundary is.
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "sort_order.asc"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        try await authorize(&request)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RewriteError.backend("Failed to load buttons.")
        }
        return try PostgRESTCoding.decoder.decode([UserPrompt].self, from: data)
    }

    // MARK: - Writes
    //
    // `user_prompts` already carries owner-scoped RLS for all four commands
    // (`select/insert/update/delete own`, verified against the live project), so
    // editing buttons from the Mac needs no migration. What it does need is care with
    // three columns:
    //
    // - `user_id` is NOT NULL with no default, so it has to be sent explicitly.
    // - `builtin_key` is CHECK-constrained to the four seeded keys, so anything
    //   authored here leaves it null.
    // - `origin` rides along with the rewrite request into analytics, and a button
    //   made on the laptop is `user_authored` — the same value the phone writes for a
    //   hand-made button.

    /// New buttons normally land in `sub`; the caller uses `main` only when creating
    /// the first button after an empty state.
    public func create(
        title: String,
        prompt: String,
        slot: UserPrompt.Slot = .sub,
        sortOrder: Int
    ) async throws -> UserPrompt {
        guard let userId = await auth.currentSession?.userId, !userId.isEmpty else {
            throw RewriteError.notSignedIn
        }

        var request = URLRequest(
            url: config.restEndpoint.appendingPathComponent("user_prompts")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        try await authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "user_id": userId,
            "slot": slot.rawValue,
            "title": title,
            "prompt": prompt,
            "is_enabled": true,
            "sort_order": sortOrder,
            "origin": PromptOrigin.userAuthored.rawValue,
        ])

        let data = try await send(request, action: "Failed to create the button.")
        guard let created = try PostgRESTCoding.decoder.decode([UserPrompt].self, from: data).first
        else {
            throw RewriteError.backend("Failed to create the button.")
        }
        return created
    }

    /// Sends the whole mutable set rather than a diff. `slot` is included because the
    /// desktop list's first row owns the iPhone's main-toolbar position.
    ///
    /// `updated_at` defaults only on insert, so a PATCH that left it alone would leave
    /// the row looking older than the phone's copy.
    public func update(_ prompt: UserPrompt) async throws {
        var request = try rowRequest(id: prompt.id, method: "PATCH")
        try await authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "title": prompt.title,
            "prompt": prompt.prompt,
            "is_enabled": prompt.isEnabled,
            "slot": prompt.slot.rawValue,
            "sort_order": prompt.sortOrder,
            "updated_at": PostgRESTCoding.timestamp(Date()),
        ])
        _ = try await send(request, action: "Failed to save the button.")
    }

    public func delete(id: UUID) async throws {
        var request = try rowRequest(id: id, method: "DELETE")
        try await authorize(&request)
        _ = try await send(request, action: "Failed to delete the button.")
    }

    /// Replaces the complete owner-scoped button configuration after onboarding
    /// review. The new rows are upserted before obsolete rows are removed, so a
    /// failed second request can leave extras but can never leave the account with
    /// no buttons. A final fetch is the caller's source of truth.
    ///
    /// The account's current rows are read first because `id` is not the table's only
    /// unique key: `user_prompts_user_builtin_unique` makes `builtin_key` an identity too,
    /// and a preset pack arrives with fresh ids for keys the phone already seeded.
    /// `UserPromptIdentity.reconciled` is what keeps that upsert an upsert — see the note
    /// there for the 409 it fixes.
    public func replaceAll(with prompts: [UserPrompt]) async throws -> [UserPrompt] {
        guard !prompts.isEmpty else {
            throw RewriteError.backend("At least one button is required.")
        }
        guard let userId = await auth.currentSession?.userId, !userId.isEmpty else {
            throw RewriteError.notSignedIn
        }

        let prompts = UserPromptIdentity.reconciled(prompts, existing: try await fetch())

        var components = URLComponents(
            url: config.restEndpoint.appendingPathComponent("user_prompts"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]

        var upsert = URLRequest(url: components.url!)
        upsert.httpMethod = "POST"
        upsert.timeoutInterval = 15
        upsert.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        try await authorize(&upsert)
        upsert.httpBody = try JSONSerialization.data(withJSONObject: prompts.map { prompt in
            [
                "id": prompt.id.uuidString,
                "user_id": userId,
                "slot": prompt.slot.rawValue,
                "builtin_key": prompt.builtinKey ?? NSNull(),
                "origin": prompt.origin.rawValue,
                "title": prompt.title,
                "prompt": prompt.prompt,
                "is_enabled": prompt.isEnabled,
                "sort_order": prompt.sortOrder,
                "created_at": PostgRESTCoding.timestamp(prompt.createdAt),
                "updated_at": PostgRESTCoding.timestamp(prompt.updatedAt),
            ] as [String: Any]
        })
        _ = try await send(upsert, action: "Failed to save the onboarding buttons.")

        var deleteComponents = URLComponents(
            url: config.restEndpoint.appendingPathComponent("user_prompts"),
            resolvingAgainstBaseURL: false
        )!
        let ids = prompts.map { $0.id.uuidString }.joined(separator: ",")
        deleteComponents.queryItems = [URLQueryItem(name: "id", value: "not.in.(\(ids))")]
        var delete = URLRequest(url: deleteComponents.url!)
        delete.httpMethod = "DELETE"
        delete.timeoutInterval = 15
        try await authorize(&delete)
        _ = try await send(delete, action: "Failed to remove the previous buttons.")

        return try await fetch()
    }

    private func rowRequest(id: UUID, method: String) throws -> URLRequest {
        var components = URLComponents(
            url: config.restEndpoint.appendingPathComponent("user_prompts"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString)")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.timeoutInterval = 15
        return request
    }

    private func send(_ request: URLRequest, action: String) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RewriteError.backend(action)
        }
        return data
    }

    private func authorize(_ request: inout URLRequest) async throws {
        let accessToken = try await auth.ensureFreshAccessToken()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

}
