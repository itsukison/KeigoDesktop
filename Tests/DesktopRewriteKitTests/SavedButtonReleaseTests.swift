import Foundation
import XCTest
@testable import DesktopRewriteKit

private final class ButtonResponseProtocol: URLProtocol, @unchecked Sendable {
    static let fixtureID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.url!.host == "failure.test" ? 500 : 200
        let body = #"[{"id":"10000000-0000-0000-0000-000000000001","slot":"main","builtin_key":"polite","title":"Polite","prompt":"Keep the meaning","is_enabled":false,"sort_order":0,"origin":"builtin","created_at":"2026-08-01T00:00:00Z","updated_at":"2026-08-02T00:00:00Z"}]"#
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class SavedButtonReleaseTests: XCTestCase {
    private func fixture(host: String = "buttons.test") -> (UserPromptRemoteStore, InMemorySessionStore, URLSession) {
        let config = SupabaseConfig(supabaseURL: URL(string: "https://\(host)")!, appVersion: "test")
        let sessions = InMemorySessionStore(session: AuthSession(accessToken: "test", refreshToken: "test", expiresAt: .distantFuture, userId: "A"))
        let auth = AuthService(config: config, store: sessions)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ButtonResponseProtocol.self]
        let transport = URLSession(configuration: configuration)
        return (UserPromptRemoteStore(config: config, auth: auth, session: transport).scoped(to: "A"), sessions, transport)
    }

    func testExistingButtonsKeepIdentityDisabledStateAndInstructions() async throws {
        let (store, _, transport) = fixture()
        defer { transport.invalidateAndCancel() }
        let loaded = try await store.fetch()
        let prompt = try XCTUnwrap(loaded.first)
        XCTAssertEqual(prompt.id, ButtonResponseProtocol.fixtureID)
        XCTAssertEqual(prompt.origin, .builtin)
        XCTAssertFalse(prompt.isEnabled)
        let reviewed = OnboardingButtonDraft(prompt: prompt).userPrompt(at: 0)
        XCTAssertEqual(reviewed.id, prompt.id)
        XCTAssertEqual(reviewed.builtinKey, prompt.builtinKey)
        XCTAssertEqual(reviewed.prompt, prompt.prompt)
        XCTAssertEqual(reviewed.createdAt, prompt.createdAt)
        XCTAssertFalse(reviewed.isEnabled)
    }

    func testScopedStoreRejectsReadsAndWritesAfterAccountSwitch() async throws {
        let (store, sessions, transport) = fixture()
        defer { transport.invalidateAndCancel() }
        let rows = try await store.fetch()
        let row = try XCTUnwrap(rows.first)
        sessions.write(AuthSession(accessToken: "other", refreshToken: "other", expiresAt: .distantFuture, userId: "B"))
        do { _ = try await store.fetch(); XCTFail("Read used a different account") } catch { }
        do { try await store.update(row); XCTFail("Update used a different account") } catch { }
        do { try await store.delete(id: row.id); XCTFail("Delete used a different account") } catch { }
        do { _ = try await store.create(title: "New", prompt: "Instruction", sortOrder: 1); XCTFail("Create used a different account") } catch { }
        do { _ = try await store.replaceAll(with: [row]); XCTFail("Replacement used a different account") } catch { }
    }

    func testFailedSaveIsReported() async throws {
        let (store, _, transport) = fixture(host: "failure.test")
        defer { transport.invalidateAndCancel() }
        do {
            try await store.update(UserPrompt(slot: .main, title: "Edited", prompt: "Keep this draft"))
            XCTFail("A failed write must not appear saved")
        } catch let error as RewriteError {
            guard case .backend = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testDragReorderPreservesIdentityAndDisabledState() throws {
        let first = UserPrompt(slot: .main, title: "First", prompt: "First instruction")
        let second = UserPrompt(slot: .sub, title: "Second", prompt: "Second instruction", isEnabled: false)
        let third = UserPrompt(slot: .sub, title: "Third", prompt: "Third instruction", sortOrder: 1)
        let moved = try XCTUnwrap(UserPromptOrder.moving([first, second, third], id: third.id, before: first.id))
        XCTAssertEqual(moved.map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(moved.map(\.slot), [.main, .sub, .sub])
        XCTAssertFalse(moved[2].isEnabled)
        XCTAssertNil(UserPromptOrder.moving(moved, id: third.id, before: third.id))
    }

    func testLegacyDraftWithoutEnabledFieldStillDecodes() throws {
        let draft = OnboardingButtonDraft(title: "New", prompt: "Instruction")
        let decoded = try JSONDecoder().decode(OnboardingButtonDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertTrue(decoded.userPrompt(at: 0).isEnabled)
    }

    func testReleaseRequestCarriesButtonPurposeWithoutUniversalStyle() throws {
        let button = OnboardingPresetPack.starter.drafts()[0].userPrompt(at: 0)
        let key = OnboardingPresetPack.buttonAnalyticsKey(for: button)
        let attempt = RewriteAttempt(type: .savedButton, isTutorial: false, buttonAnalyticsKey: key)
        let request = RewriteRequest(prompt: button.prompt, text: "A real draft", appVersion: "test", captureMode: .wholeInput,
            attemptId: attempt.id.uuidString, rewriteType: attempt.type.rawValue, buttonAnalyticsKey: key)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertNil(object["writingStyle"])
        XCTAssertEqual(object["prompt"] as? String, button.prompt)
        XCTAssertEqual(object["buttonAnalyticsKey"] as? String, key)
        XCTAssertEqual(object["rewriteType"] as? String, "saved_button")
        XCTAssertEqual(object["attemptId"] as? String, attempt.id.uuidString)
    }
}
