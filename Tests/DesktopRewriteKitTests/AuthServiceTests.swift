import XCTest
@testable import DesktopRewriteKit

/// The two sign-up endings and the claim reader behind the account page's address.
final class AuthServiceTests: XCTestCase {

    // MARK: - JWT claims

    /// Supabase pads nothing and uses the URL alphabet, so a payload containing a
    /// `+` or `/` byte decodes to nil unless both are undone. `@` in an address is a
    /// reliable way to produce one.
    func testReadsSubAndEmailFromAnUnpaddedBase64URLPayload() throws {
        let token = Self.jwt(["sub": "8c7f0e1a-1111-2222-3333-444455556666", "email": "itsuki@example.co.jp"])

        XCTAssertEqual(
            AuthService.userId(fromJWT: token),
            "8c7f0e1a-1111-2222-3333-444455556666"
        )
        XCTAssertEqual(AuthService.claim("email", fromJWT: token), "itsuki@example.co.jp")
    }

    func testMissingClaimIsNilRatherThanACrash() throws {
        let token = Self.jwt(["sub": "abc"])
        XCTAssertNil(AuthService.claim("email", fromJWT: token))
    }

    func testMalformedTokenIsNil() {
        XCTAssertNil(AuthService.claim("email", fromJWT: "not-a-jwt"))
    }

    // MARK: - Sign-up

    /// "Confirm email" on the project returns a user row and no session. That is a
    /// success — the account exists — so `decodeSession` must fail rather than
    /// half-decode, which is what `signUp` branches on.
    func testConfirmationResponseIsNotASession() {
        let body = """
        {"id":"8c7f0e1a-1111-2222-3333-444455556666","email":"a@example.com","role":"authenticated"}
        """
        XCTAssertThrowsError(try AuthService.decodeSession(from: Data(body.utf8)))
    }

    func testMapsTheErrorCodeForAnAlreadyRegisteredAddress() {
        let body = #"{"code":422,"error_code":"user_already_exists","msg":"User already registered"}"#
        XCTAssertEqual(
            AuthService.signUpError(from: Data(body.utf8), statusCode: 422),
            .emailAlreadyRegistered
        )
    }

    /// Older GoTrue deployments send only `msg`, so the string is read as well as the
    /// code — dropping one of the two turns an actionable error into a generic one.
    func testFallsBackToTheMessageWhenThereIsNoErrorCode() {
        let body = #"{"code":400,"msg":"User already registered"}"#
        XCTAssertEqual(
            AuthService.signUpError(from: Data(body.utf8), statusCode: 400),
            .emailAlreadyRegistered
        )
    }

    func testMapsWeakPassword() {
        let body = #"{"error_code":"weak_password","msg":"Password should be at least 6 characters"}"#
        XCTAssertEqual(
            AuthService.signUpError(from: Data(body.utf8), statusCode: 422),
            .weakPassword
        )
    }

    func testUnrecognisedFailureCarriesTheStatusCode() {
        XCTAssertEqual(
            AuthService.signUpError(from: Data("{}".utf8), statusCode: 500),
            .network("signup 500")
        )
    }

    // MARK: - Hosts

    /// The sign-in host is the one string macOS shows the user before the browser
    /// opens, so it is pinned rather than left to whatever `supabaseURL` happens to be.
    func testAuthEndpointIsOnTheCustomDomain() {
        let config = SupabaseConfig(appVersion: "1.0")

        XCTAssertEqual(
            config.authEndpoint.absoluteString,
            "https://auth.keigobutton.com/auth/v1"
        )
    }

    /// The other half of the same decision: nothing a user reads goes through REST or
    /// Functions, so both stay on Supabase's own domain rather than behind our DNS.
    func testRestAndFunctionsStayOnTheProjectDomain() {
        let config = SupabaseConfig(appVersion: "1.0")

        XCTAssertEqual(config.restEndpoint.host, "eercsucvxnszqletxued.supabase.co")
        XCTAssertEqual(config.rewriteEndpoint.host, "eercsucvxnszqletxued.supabase.co")
        XCTAssertEqual(
            config.rewriteEndpoint.absoluteString,
            "https://eercsucvxnszqletxued.supabase.co/functions/v1/desktop-rewrite"
        )
    }

    /// Collapsing the two back into one field would silently undo the custom domain —
    /// every call would still work, and the alert would go back to reading
    /// `eercsucvxnszqletxued.supabase.co`. This is the test that fails when that happens.
    func testTheAuthHostIsNotTheProjectHost() {
        let config = SupabaseConfig(appVersion: "1.0")

        XCTAssertNotEqual(config.authURL.host, config.supabaseURL.host)
    }

    /// `authorizeURL` is the URL handed to `ASWebAuthenticationSession`, so its host is
    /// literally what the consent alert quotes. The callback is unchanged: the custom
    /// domain moves where the browser goes, not where it comes back to.
    func testAuthorizeURLIsBuiltOnTheAuthHostAndKeepsTheAppCallback() async {
        let service = AuthService(
            config: SupabaseConfig(appVersion: "1.0"),
            store: InMemorySessionStore()
        )

        let url = await service.authorizeURL(provider: "google")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        XCTAssertEqual(components?.host, "auth.keigobutton.com")
        XCTAssertEqual(components?.path, "/auth/v1/authorize")
        XCTAssertEqual(
            components?.queryItems?.first { $0.name == "provider" }?.value,
            "google"
        )
        XCTAssertEqual(
            components?.queryItems?.first { $0.name == "redirect_to" }?.value,
            "keigobutton://auth-callback"
        )
    }

    /// The two hosts are independent inputs, not one derived from the other — a staging
    /// or local auth host must not drag REST and Functions along with it.
    func testTheTwoHostsAreConfiguredIndependently() {
        let config = SupabaseConfig(
            authURL: URL(string: "http://127.0.0.1:54321")!,
            appVersion: "1.0"
        )

        XCTAssertEqual(config.authEndpoint.absoluteString, "http://127.0.0.1:54321/auth/v1")
        XCTAssertEqual(config.restEndpoint.host, "eercsucvxnszqletxued.supabase.co")
    }

    // MARK: -

    private static func jwt(_ claims: [String: String]) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: claims)
        let encoded = payload.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "header.\(encoded).signature"
    }
}
