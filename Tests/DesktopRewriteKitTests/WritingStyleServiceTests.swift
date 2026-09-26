import Foundation
import XCTest
@testable import DesktopRewriteKit

private final class StyleResponseProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url!.host!
        let headers = host == "supported.test" ? ["X-Desktop-Style-Version": "1"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"candidates":[{"replacement":"Result","changed":true}],"language":"en"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private struct StyleTestSessionStore: SessionStoring {
    func read() -> AuthSession? { AuthSession(accessToken: "test", refreshToken: "test", expiresAt: .distantFuture, userId: "A") }
    func write(_ session: AuthSession) {}
    func clear() {}
}
final class WritingStyleServiceTests: XCTestCase {
    func testStyledRequestsRequireServerMarkerAndLegacyRequestsDoNot() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StyleResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for supported in [true, false] {
            let config = SupabaseConfig(supabaseURL: URL(string: supported ? "https://supported.test" : "https://old.test")!, appVersion: "test")
            let auth = AuthService(config: config, store: StyleTestSessionStore())
            let service = DesktopRewriteService(config: config, auth: auth, session: session)
            let style = ResolvedWritingStyle(profile: WritingStyleProfile(context: .email), source: .knownSurface)
            let request = RewriteRequest(prompt: "", text: "Draft", appVersion: "test", candidateCount: 1, captureMode: .wholeInput, writingStyle: style)
            do {
                let result = try await service.rewrite(request)
                XCTAssertTrue(supported)
                XCTAssertEqual(result.candidates.first?.replacement, "Result")
            } catch {
                XCTAssertFalse(supported)
                guard case RewriteError.backend = error else { return XCTFail("Unexpected error: \(error)") }
            }
            let legacy = RewriteRequest(prompt: "Polish", text: "Draft", appVersion: "test", captureMode: .wholeInput)
            let result = try await service.rewrite(legacy)
            XCTAssertEqual(result.candidates.count, 1)
        }
    }
}
