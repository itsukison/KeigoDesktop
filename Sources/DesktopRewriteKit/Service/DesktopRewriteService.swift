import Foundation

public enum RewriteError: Error, Equatable, Sendable {
    case notSignedIn
    case rateLimited(String)
    /// A 429 the server could attribute. `docs/billing.md` §6 makes the distinction
    /// structural rather than cosmetic: a monthly cap and an abuse brake are opposite
    /// problems with opposite answers, and a bare 429 tells them apart in neither the
    /// UI nor the data.
    case quotaExceeded(QuotaDenial)
    case contentBlocked(String)
    case backend(String)
    case invalidResponse
}

/// Why a rewrite was refused, and everything the cap-hit surface needs to say so.
///
/// `resetsAt` is not decoration and not optional in spirit: §4.5's clearest finding
/// is that the driver of billing support tickets is an **invisible reset date**, not
/// the lock itself. A Pro window resets on the subscription anchor and a free one on
/// the 1st, so there is no fixed date that is true for both users — only the server
/// knows, and this is how it says.
public struct QuotaDenial: Equatable, Sendable {

    public enum Reason: String, Sendable {
        /// The marketed allowance — 50 free, 1,000 Pro.
        case month = "quota_month"
        /// The anti-abuse brakes. A different message and a different `reason` in
        /// analytics, because upgrading does not fix them.
        case day = "brake_day"
        case hour = "brake_hour"
        case minute = "brake_minute"
    }

    public let reason: Reason
    public let plan: Entitlement.Plan
    public let used: Int?
    public let monthLimit: Int?
    public let resetsAt: Date?
    /// The server's own wording, used when there is nothing better to compose.
    public let message: String

    public init(
        reason: Reason,
        plan: Entitlement.Plan,
        used: Int?,
        monthLimit: Int?,
        resetsAt: Date?,
        message: String
    ) {
        self.reason = reason
        self.plan = plan
        self.used = used
        self.monthLimit = monthLimit
        self.resetsAt = resetsAt
        self.message = message
    }

    /// §9 row 41 vs row 42. A free user who hits 50 has somewhere to go; a Pro user
    /// who hits 1,000 does not — there is no tier above, so showing them a paywall
    /// would be selling them what they already own.
    public var offersUpgrade: Bool {
        reason == .month && plan == .free
    }
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
            // An unattributed 429 is still possible — the guard itself can be
            // unreachable, and `reason` is null in that case. It stays `rateLimited`
            // rather than being forced into a denial, because "we could not measure
            // you" is not "you are out of rewrites" and must not open a paywall.
            if let denial = payload?.denial(message: message) {
                throw RewriteError.quotaExceeded(denial)
            }
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

    /// The 429 body carries the denial alongside the error, rather than replacing it:
    /// every existing client keeps reading `error.message` and the new fields are
    /// additive.
    private struct ErrorPayload: Decodable {
        struct Body: Decodable {
            let code: String?
            let message: String
        }
        let error: Body
        let reason: String?
        let plan: String?
        let used: Int?
        let monthLimit: Int?
        let resetsAt: String?

        func denial(message: String) -> QuotaDenial? {
            guard let reason = reason.flatMap(QuotaDenial.Reason.init(rawValue:)) else {
                return nil
            }
            return QuotaDenial(
                reason: reason,
                plan: plan.flatMap(Entitlement.Plan.init(rawValue:)) ?? .free,
                used: used,
                monthLimit: monthLimit,
                resetsAt: resetsAt.flatMap(PostgRESTCoding.date(from:)),
                message: message
            )
        }
    }
}
