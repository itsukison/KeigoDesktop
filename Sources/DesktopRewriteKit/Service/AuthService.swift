import Foundation

public enum AuthError: Error, Equatable, Sendable {
    case notSignedIn
    case invalidCredentials
    case emailAlreadyRegistered
    case weakPassword
    case network(String)
}

/// Sign-up has two successful endings, and the caller has to render both.
///
/// With "Confirm email" enabled on the project, `/signup` returns a user row and no
/// session — the account exists but nothing is signed in until the link in the mail
/// is clicked. Treating that as a failure would tell a user their account was not
/// created when it was.
public enum SignUpOutcome: Equatable, Sendable {
    case signedIn(AuthSession)
    case confirmationRequired
}

/// Supabase auth over plain `URLSession`.
///
/// Hand-rolled rather than pulling in `supabase-swift`, for the same reason
/// `CloudRewriteService` on iOS is: the surface we need is three REST calls, and the
/// token-refresh timing in `ensureFreshAccessToken` is behaviour we want to own and
/// test rather than inherit.
public actor AuthService {

    private let config: SupabaseConfig
    private let store: SessionStoring
    private let session: URLSession

    /// Coalesces concurrent refreshes. Two buttons pressed in the same second must
    /// not both spend the refresh token — Supabase rotates it, so the loser of that
    /// race would write back a token the server has already invalidated.
    private var inFlightRefresh: Task<String, Error>?

    public init(
        config: SupabaseConfig,
        store: SessionStoring = KeychainSessionStore(),
        session: URLSession = .shared
    ) {
        self.config = config
        self.store = store
        self.session = session
    }

    public var currentSession: AuthSession? {
        store.read()
    }

    public var isSignedIn: Bool {
        store.read() != nil
    }

    /// The address the account page shows.
    ///
    /// Read out of the access token rather than from `GET /auth/v1/user`: the claim is
    /// already in hand, it costs no round trip, and it is still correct offline. The
    /// alternative — widening `AuthSession` — would change the Keychain payload and
    /// invalidate every session already stored on disk.
    public var currentEmail: String? {
        store.read().flatMap { Self.claim("email", fromJWT: $0.accessToken) }
    }

    public func signOut() {
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        store.clear()
    }

    // MARK: - Access token

    /// Mirrors `CloudRewriteService.ensureFreshAccessToken()`: refresh when within
    /// 30 s of expiry, and fall back to the existing token if the refresh fails
    /// rather than forcing a sign-out on a flaky network.
    public func ensureFreshAccessToken() async throws -> String {
        guard let current = store.read() else { throw AuthError.notSignedIn }

        if Date().addingTimeInterval(30) < current.expiresAt {
            return current.accessToken
        }

        if let existing = inFlightRefresh {
            return try await existing.value
        }

        let task = Task<String, Error> { [config, store, session] in
            do {
                let refreshed = try await Self.refresh(
                    refreshToken: current.refreshToken,
                    config: config,
                    session: session
                )
                store.write(refreshed)
                return refreshed.accessToken
            } catch {
                return current.accessToken
            }
        }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        return try await task.value
    }

    // MARK: - Sign in

    /// Email + password, matching `UserSession.signIn(email:password:)` on iOS.
    public func signIn(email: String, password: String) async throws -> AuthSession {
        let body: [String: Any] = ["email": email, "password": password]
        let session = try await token(grantType: "password", body: body)
        store.write(session)
        return session
    }

    /// Creating an account from the Mac.
    ///
    /// `/signup` is a different endpoint from `/token`, and its failures are the ones
    /// worth naming: "already registered" and "too short" are both things the user can
    /// act on, and a generic "サインアップできませんでした" would hide which.
    public func signUp(email: String, password: String) async throws -> SignUpOutcome {
        var request = URLRequest(url: config.authEndpoint.appendingPathComponent("signup"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["email": email, "password": password]
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.signUpError(from: data, statusCode: http.statusCode)
        }

        guard let created = try? Self.decodeSession(from: data) else {
            return .confirmationRequired
        }
        store.write(created)
        return .signedIn(created)
    }

    /// GoTrue moved from `msg` strings to stable `error_code` values, and older
    /// deployments still send only the former, so both are read.
    static func signUpError(from data: Data, statusCode: Int) -> AuthError {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (json["error_code"] as? String) ?? (json["code"] as? String) ?? ""
        let message = (json["msg"] as? String)
            ?? (json["message"] as? String)
            ?? (json["error_description"] as? String)
            ?? ""

        if code == "user_already_exists" || code == "email_exists"
            || message.localizedCaseInsensitiveContains("already registered")
            || message.localizedCaseInsensitiveContains("already been registered") {
            return .emailAlreadyRegistered
        }
        if code == "weak_password" || message.localizedCaseInsensitiveContains("password should be") {
            return .weakPassword
        }
        return .network("signup \(statusCode)")
    }

    /// Apple sign-in. The iOS app uses `signInWithIdToken` with an Apple identity
    /// token; the REST equivalent is the `id_token` grant, so the same `auth.users`
    /// row is reached from either surface — which is the point of §6's shared login.
    public func signInWithApple(idToken: String, nonce: String?) async throws -> AuthSession {
        var body: [String: Any] = ["provider": "apple", "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        let session = try await token(grantType: "id_token", body: body)
        store.write(session)
        return session
    }

    /// Completes the `ASWebAuthenticationSession` leg of an OAuth sign-in. Supabase
    /// returns tokens in the URL *fragment*, which `URLComponents` does not parse
    /// into query items, so it is split by hand.
    public func completeOAuthCallback(url: URL) throws -> AuthSession {
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            throw AuthError.invalidCredentials
        }
        let pairs = fragment.split(separator: "&").reduce(into: [String: String]()) { acc, pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { return }
            acc[String(parts[0])] = String(parts[1])
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding
        }

        guard let accessToken = pairs["access_token"],
              let refreshToken = pairs["refresh_token"]
        else { throw AuthError.invalidCredentials }

        let expiresIn = Double(pairs["expires_in"] ?? "3600") ?? 3600
        let session = AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            userId: Self.userId(fromJWT: accessToken) ?? ""
        )
        store.write(session)
        return session
    }

    /// The URL to open in `ASWebAuthenticationSession`.
    ///
    /// Its host is what macOS quotes back at the user in the consent alert, which is
    /// why it comes from `config.authEndpoint` (the custom domain) rather than from
    /// `config.supabaseURL`. `redirect_to` is unaffected — the browser still comes back
    /// to this app's own scheme.
    public func authorizeURL(provider: String) -> URL {
        var components = URLComponents(
            url: config.authEndpoint.appendingPathComponent("authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: "keigobutton://auth-callback"),
        ]
        return components.url!
    }

    // MARK: - Wire

    private func token(grantType: String, body: [String: Any]) async throws -> AuthSession {
        var components = URLComponents(
            url: config.authEndpoint.appendingPathComponent("token"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.network("No HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw http.statusCode == 400 || http.statusCode == 401
                ? AuthError.invalidCredentials
                : AuthError.network("auth \(http.statusCode)")
        }
        return try Self.decodeSession(from: data)
    }

    private static func refresh(
        refreshToken: String,
        config: SupabaseConfig,
        session: URLSession
    ) async throws -> AuthSession {
        var components = URLComponents(
            url: config.authEndpoint.appendingPathComponent("token"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.publishableKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["refresh_token": refreshToken]
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AuthError.notSignedIn
        }
        return try decodeSession(from: data)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Double
        let user: User?

        struct User: Decodable { let id: String }
    }

    static func decodeSession(from data: Data) throws -> AuthSession {
        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        return AuthSession(
            accessToken: payload.access_token,
            refreshToken: payload.refresh_token,
            expiresAt: Date().addingTimeInterval(payload.expires_in),
            userId: payload.user?.id ?? userId(fromJWT: payload.access_token) ?? ""
        )
    }

    /// Reads `sub` out of the JWT payload. The refresh grant does not always echo a
    /// `user` object, and the id is needed as the PostHog `distinct_id` (§7).
    static func userId(fromJWT token: String) -> String? {
        claim("sub", fromJWT: token)
    }

    /// The payload is base64**url**, which `Data(base64Encoded:)` does not accept and
    /// which is unpadded — both have to be undone before decoding.
    static func claim(_ name: String, fromJWT token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }

        var base64 = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)

        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json[name] as? String
    }
}
