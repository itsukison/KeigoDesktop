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

    /// New buttons land in `sub`. `main` is the phone's primary toolbar slot; the
    /// hover row flattens both anyway (`enabledForHoverRow`), so claiming `main` from
    /// the desktop would reshuffle the iOS toolbar for no gain here.
    public func create(title: String, prompt: String, sortOrder: Int) async throws -> UserPrompt {
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
            "slot": UserPrompt.Slot.sub.rawValue,
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

    /// Sends the whole mutable set rather than a diff — the caller is a form, and the
    /// four fields together are one edit.
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
