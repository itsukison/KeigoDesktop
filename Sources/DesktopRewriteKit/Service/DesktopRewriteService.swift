import Foundation

public enum RewriteError: Error, Equatable, Sendable {
    case notSignedIn
    case rateLimited(String)
    case contentBlocked(String)
    case backend(String)
    case invalidResponse
}

/// Client for the `desktop-rewrite` Edge Function (§6).
///
/// Auth is identical to the keyboard: the user's JWT plus the publishable key. No
/// provider key ever reaches this process — §2.
public struct DesktopRewriteService: Sendable {

    private let config: SupabaseConfig
    private let auth: AuthService
    private let session: URLSession

    public init(config: SupabaseConfig, auth: AuthService, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    public func rewrite(_ request: RewriteRequest) async throws -> RewriteResult {
        let data = try await post(
            to: config.rewriteEndpoint,
            body: try JSONEncoder().encode(request),
            timeout: 25
        )
        guard let result = try? JSONDecoder().decode(RewriteResult.self, from: data) else {
            throw RewriteError.invalidResponse
        }
        return result
    }

    // MARK: - Feedback

    /// §6: `result.png`'s 👍/👎 and the accepted-candidate signal. Implemented from
    /// day one rather than deferred — the iOS side has carried this as an open
    /// production item for months precisely because it was left for later.
    public func submitSelection(eventId: String, selectedIndex: Int) async throws {
        _ = try? await post(
            to: config.rewriteEndpoint,
            body: try JSONEncoder().encode(
                SelectionFeedback(eventId: eventId, selectedIndex: selectedIndex)
            ),
            timeout: 10
        )
    }

    public func submitAction(
        eventId: String,
        action: String,
        selectedIndex: Int?,
        latencyMs: Int?
    ) async throws {
        _ = try? await post(
            to: config.rewriteEndpoint,
            body: try JSONEncoder().encode(
                ActionFeedback(
                    eventId: eventId,
                    action: action,
                    selectedIndex: selectedIndex,
                    latencyMs: latencyMs
                )
            ),
            timeout: 10
        )
    }

    // MARK: - Wire

    private func post(to url: URL, body: Data, timeout: TimeInterval) async throws -> Data {
        let accessToken: String
        do {
            accessToken = try await auth.ensureFreshAccessToken()
        } catch {
            throw RewriteError.notSignedIn
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(config.publishableKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = timeout
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw RewriteError.invalidResponse
        }
        if (200..<300).contains(http.statusCode) { return data }

        let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data)
        let message = payload?.error.message ?? "書き換えに失敗しました。"
        switch payload?.error.code {
        case "rate_limited":
            throw RewriteError.rateLimited(message)
        case "content_blocked":
            throw RewriteError.contentBlocked(message)
        default:
            throw RewriteError.backend(message)
        }
    }

    private struct SelectionFeedback: Encodable {
        let eventId: String
        let selectedIndex: Int
    }

    private struct ActionFeedback: Encodable {
        let eventId: String
        let action: String
        let selectedIndex: Int?
        let latencyMs: Int?
    }

    private struct ErrorPayload: Decodable {
        struct Body: Decodable {
            let code: String?
            let message: String
        }
        let error: Body
    }
}
