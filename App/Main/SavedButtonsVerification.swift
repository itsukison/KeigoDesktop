#if DEBUG
import AppKit
import DesktopRewriteKit

/// Offline native-model integration checks. Never initializes production services.
@MainActor enum SavedButtonsVerification {
    static var isRunning: Bool { ProcessInfo.processInfo.arguments.contains("--verify-saved-buttons") }
    static func run() async throws {
        let config = SupabaseConfig(supabaseURL: URL(string: "https://buttons.invalid")!, appVersion: "fixture")
        let sessions = InMemorySessionStore(session: AuthSession(accessToken: "A", refreshToken: "A", expiresAt: .distantFuture, userId: "A"))
        let auth = AuthService(config: config, store: sessions)
        let transportConfig = URLSessionConfiguration.ephemeral
        transportConfig.protocolClasses = [ButtonsFixtureProtocol.self]
        let transport = URLSession(configuration: transportConfig)
        defer { transport.invalidateAndCancel() }
        let model = MainModel(auth: auth, promptStore: UserPromptRemoteStore(config: config, auth: auth, session: transport),
            profileStore: ProfileRemoteStore(config: config, auth: auth), billingStore: BillingRemoteStore(config: config, auth: auth),
            history: RewriteHistoryStore(directory: URL(fileURLWithPath: "/private/tmp/keigo-button-fixture-history")),
            appVersion: "fixture", onPromptsChanged: {}, automaticallyRefresh: false)
        await model.reloadPrompts()
        let original = model.prompts
        precondition(original.count == 3)
        let invalid = await model.saveButton(nil, title: " ", instruction: "content")
        precondition(!invalid && ButtonsFixtureProtocol.state.writeCount == 0)
        let saved = await model.saveButton(original[0], title: "Edited", instruction: "My custom instruction")
        precondition(saved && model.prompts[0].id == original[0].id && model.prompts[0].builtinKey == original[0].builtinKey)
        await model.reloadPrompts()
        precondition(model.prompts[0].prompt == "My custom instruction")
        model.setEnabled(model.prompts[0], false)
        try await settle(model)
        precondition(!model.prompts[0].isEnabled)
        model.movePrompt(id: original[2].id, by: -1)
        model.movePrompt(id: original[2].id, by: -1)
        try await settle(model)
        precondition(model.prompts.map(\.id) == [original[2].id, original[0].id, original[1].id])
        precondition(model.prompts.map(\.slot) == [.main, .sub, .sub])
        precondition(!model.prompts[1].isEnabled)
        let created = await model.saveButton(nil, title: " New ", instruction: " New instruction ")
        precondition(created && model.prompts.last?.title == "New")
        model.delete(model.prompts.last!)
        try await settle(model)
        precondition(model.prompts.count == 3)
        ButtonsFixtureProtocol.state.failNextWrite = true
        let failed = await model.saveButton(model.prompts[0], title: "Unsaved", instruction: "Keep my draft")
        precondition(!failed && model.prompts[0].title != "Unsaved" && model.promptsError != nil)
        ButtonsFixtureProtocol.state.failNextWrite = true
        model.movePrompt(id: original[1].id, by: -1)
        try await settle(model)
        precondition(model.prompts.map(\.id) == [original[2].id, original[0].id, original[1].id] && model.promptsError != nil)
        // An old response is deliberately held until the replacement account has loaded.
        ButtonsFixtureProtocol.state.delayNextRead = true
        let oldRead = Task { await model.reloadPrompts() }
        try await Task.sleep(for: .milliseconds(80))
        sessions.write(AuthSession(accessToken: "B", refreshToken: "B", expiresAt: .distantFuture, userId: "B"))
        await model.reloadPrompts()
        await oldRead.value
        precondition(model.prompts.isEmpty)
        let report = "PASS: valid Save/reload, rejected blank creation, identities preserved, enable/disable, coalesced reorder persistence, main slot, Add/Delete, failed Save, failed reorder reconciliation, stale account response.\nNo production network, credentials, or analytics initialization.\n"
        try report.write(toFile: "/private/tmp/keigo-saved-buttons-verification.txt", atomically: true, encoding: .utf8)
    }
    private static func settle(_ model: MainModel) async throws {
        for _ in 0..<200 {
            if !model.isSavingButtons && !model.isReorderingButtons { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw URLError(.timedOut)
    }
}

private final class ButtonsFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var rows = OnboardingPresetPack.starter.drafts().prefix(3).enumerated().map { $0.element.userPrompt(at: $0.offset) }
    private var writes = 0
    private var fail = false
    private var delay = false
    var writeCount: Int { lock.withLock { writes } }
    var failNextWrite: Bool { get { lock.withLock { fail } } set { lock.withLock { fail = newValue } } }
    var delayNextRead: Bool { get { lock.withLock { delay } } set { lock.withLock { delay = newValue } } }
    func response(_ request: URLRequest) throws -> (Int, Data, Bool) {
        try lock.withLock {
            let method = request.httpMethod ?? "GET"
            if method != "GET" { writes += 1; if fail { fail = false; return (500, Data(), false) } }
            let shouldDelay = method == "GET" && delay
            if shouldDelay { delay = false }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer B" { return (200, Data("[]".utf8), false) }
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
                body = data
            }
            let fields = try body.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
            let filter = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value
            let id = filter.flatMap { UUID(uuidString: String($0.dropFirst(3))) }
            switch method {
            case "PATCH":
                if let index = rows.firstIndex(where: { $0.id == id }), let fields {
                    rows[index].title = fields["title"] as! String; rows[index].prompt = fields["prompt"] as! String
                    rows[index].isEnabled = fields["is_enabled"] as! Bool
                    rows[index].slot = UserPrompt.Slot(rawValue: fields["slot"] as! String)!
                    rows[index].sortOrder = fields["sort_order"] as! Int
                }
            case "DELETE": rows.removeAll { $0.id == id }
            case "POST":
                if let fields { rows.append(UserPrompt(slot: .init(rawValue: fields["slot"] as! String)!, title: fields["title"] as! String, prompt: fields["prompt"] as! String, sortOrder: fields["sort_order"] as! Int)) }
            default: break
            }
            let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase; encoder.dateEncodingStrategy = .iso8601
            return (200, try encoder.encode(method == "POST" ? [rows.last!] : rows), shouldDelay)
        }
    }
}
private final class ButtonsFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = ButtonsFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data, delay) = try Self.state.response(request)
            DispatchQueue.global().asyncAfter(deadline: .now() + (delay ? 0.35 : 0)) { [self] in
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
            }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
