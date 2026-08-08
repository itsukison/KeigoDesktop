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
