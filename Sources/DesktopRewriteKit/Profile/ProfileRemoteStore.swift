import Foundation

/// The shared `profiles` row (§6): one identity across phone and laptop.
///
/// The live table is exactly three columns — `id`, `display_name` (NOT NULL,
/// defaults to `''`) and `created_at`. There is no plan, no avatar and no
/// subscription column, so the account page shows a name, an address and a join
/// date; anything more would need a migration in the iOS repo, not a view here.
public struct Profile: Codable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public let createdAt: Date

    public init(id: UUID, displayName: String, createdAt: Date) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
    }
}

public struct ProfileRemoteStore: Sendable {

    private let config: SupabaseConfig
    private let auth: AuthService
    private let session: URLSession

    public init(config: SupabaseConfig, auth: AuthService, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    /// Nil when the account has no row yet — a user created on this Mac has not
    /// necessarily been through the phone's onboarding, which is what writes it.
    /// `save` upserts, so the missing row is not an error state to recover from.
    public func fetch() async throws -> Profile? {
        var components = URLComponents(
            url: config.restEndpoint.appendingPathComponent("profiles"),
            resolvingAgainstBaseURL: false
        )!
        // RLS scopes this to the caller's row, so no explicit id filter is needed —
        // and adding one would misstate where the boundary actually is.
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "limit", value: "1"),
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        try await authorize(&request)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RewriteError.backend("Failed to load the profile.")
        }
        return try PostgRESTCoding.decoder.decode([Profile].self, from: data).first
    }

    /// Upsert rather than PATCH: `profiles_insert_own` exists precisely because the
    /// row may not be there, and a PATCH against nothing succeeds with zero rows
    /// affected — a save that silently does nothing.
    public func setDisplayName(_ name: String) async throws {
        guard let userId = await auth.currentSession?.userId, !userId.isEmpty else {
            throw RewriteError.notSignedIn
        }

        var request = URLRequest(url: config.restEndpoint.appendingPathComponent("profiles"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(
            "resolution=merge-duplicates,return=minimal",
            forHTTPHeaderField: "Prefer"
        )
        try await authorize(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "id": userId,
            "display_name": name,
        ])

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw RewriteError.backend("Failed to save the name.")
        }
    }

    private func authorize(_ request: inout URLRequest) async throws {
        let accessToken = try await auth.ensureFreshAccessToken()
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
}
