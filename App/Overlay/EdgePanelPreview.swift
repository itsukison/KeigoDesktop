#if DEBUG
import AppKit
import DesktopRewriteKit
import SwiftUI
import TextIO

@MainActor final class EdgePanelPreview: NSObject, NSWindowDelegate {
    static var isRunning: Bool {
        ProcessInfo.processInfo.arguments.contains("--preview-edge-panels") || renders || verifiesPolish
    }
    static var renders: Bool { ProcessInfo.processInfo.arguments.contains("--render-edge-panels") }
    static var verifiesPolish: Bool { ProcessInfo.processInfo.arguments.contains("--verify-polish-guidance") }
    private static var retained: EdgePanelPreview?
    let controller: OverlayController
    private let window: NSWindow
    private let output = URL(fileURLWithPath: "/private/tmp/keigo-edge-previews", isDirectory: true)

    static func show() {
        let preview = EdgePanelPreview()
        retained = preview
        if renders || verifiesPolish {
            Task { @MainActor in
                do {
                    if verifiesPolish { try await preview.verifyPolish() }
                    else { try await preview.render() }
                }
                catch { NSLog("Edge preview failed: %@", String(describing: error)) }
                NSApp.terminate(nil)
            }
        } else {
            preview.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    override init() {
        let config = SupabaseConfig(supabaseURL: URL(string: "http://127.0.0.1:1")!,
            authURL: URL(string: "http://127.0.0.1:1")!, publishableKey: "preview", appVersion: "preview")
        let auth = AuthService(config: config, store: InMemorySessionStore(session: AuthSession(
            accessToken: "preview", refreshToken: "preview", expiresAt: .distantFuture, userId: "preview")))
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [EdgePreviewProtocol.self]
        controller = OverlayController(rewriteService: DesktopRewriteService(config: config, auth: auth,
            session: URLSession(configuration: sessionConfig)), auth: auth,
            promptStore: UserPromptRemoteStore(config: config, auth: auth, session: URLSession(configuration: sessionConfig)),
            analytics: EdgePreviewAnalytics(), history: RewriteHistoryStore(directory: output.appendingPathComponent("history")),
            appVersion: "preview")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Edge panels — isolated native preview"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: EdgePreviewControls { [weak self] zone, fixture, language in
            guard let self else { return }
            AppLanguageState.current = language
            EdgePreviewProtocol.mode.set(fixture == 3 ? "hold" : "success")
            self.controller.configureEdgePreview(context: self.fixture(fixture == 3 ? 0 : fixture), zone: zone)
            if fixture == 3 { self.controller.regenerate() }
        })
    }

    private func fixture(_ kind: Int) -> ResultContext {
        let instruction = kind == 0 ? ResultInstruction.hidden : .input(tr(
            "丁寧で親しみやすく、来週の打ち合わせを提案してください。",
            "Keep it warm and professional, and suggest a meeting next week.",
            "请保持友好、专业的语气，并建议下周开会。"))
        let paragraph = tr(
            "ご連絡ありがとうございます。ぜひ来週、詳しくお話しできればと思います。ご都合のよい日時をお知らせいただけますか。\n\nどうぞよろしくお願いいたします。",
            "Thanks for getting in touch. I'd be happy to discuss this further next week. Could you let me know a time that works for you?\n\nLooking forward to speaking with you.",
            "感谢您的联系。我很乐意在下周进一步讨论。请问您什么时候方便？\n\n期待与您交流。")
        let text = kind == 2 ? Array(repeating: paragraph, count: 7).joined(separator: "\n\n") + "\n\nEND — 最後の行 — 最后一行" : paragraph
        let pending = PendingRewrite(captured: CapturedTarget(target: TextTarget(text: "Fixture draft",
            captureMode: .wholeInput, path: .ax, writeStrategy: .none), frontmostPID: nil),
            requestText: "Fixture draft", promptText: instruction.text ?? "", instruction: instruction,
            replyTo: nil, replyContext: nil, draftReadStatus: nil, buttonTitle: kind == 0 ? "Make polite" : nil,
            attempt: RewriteAttempt(type: kind == 0 ? .savedButton : .customInstruction, isTutorial: true), startedAt: Date())
        return ResultContext(pending: pending, result: RewriteResult(candidates: [RewriteCandidate(replacement: text, changed: true)],
            language: AppLanguageState.current.writingLanguageCode), historyEntryId: nil)
    }

    private func verifyFrame(_ actual: NSRect, expected: NSRect, context: String) throws {
        guard abs(actual.minX - expected.minX) <= 0.5, abs(actual.minY - expected.minY) <= 0.5,
              abs(actual.width - expected.width) <= 0.5, abs(actual.height - expected.height) <= 0.5 else {
            throw PreviewError.failed("\(context): frame \(actual), expected \(expected)")
        }
    }

    private func verifyPolish() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        await controller.refreshAccount()
        var report: [String] = []
        let rejected: [(String, Result<TextTarget, TextIOError>)] = [
            ("missing", .success(TextTarget(text: "", captureMode: .wholeInput, path: .ax, writeStrategy: .none))),
            ("empty", .success(TextTarget(text: "", captureMode: .wholeInput, path: .ax, writeStrategy: .clipboard))),
            ("whitespace", .success(TextTarget(text: " \n\t", captureMode: .wholeInput, path: .ax, writeStrategy: .ax))),
            ("excluded", .success(TextTarget(text: "Search", captureMode: .wholeInput, path: .ax,
                                           writeStrategy: .ax, writingSurfaceHint: .excluded))),
            ("permission", .failure(.notTrusted))
        ]
        for language in AppLanguage.allCases {
            AppLanguageState.current = language
            for zone in SnapZone.allCases {
                for (name, capture) in rejected {
                    controller.dismiss()
                    controller.prepareReplyPreview(zone: zone)
                    controller.mouseEntered()
                    controller.previewWritingCapture = capture
                    let keyWindow = NSApp.keyWindow
                    let requestCount = EdgePreviewProtocol.mode.requestCount
                    controller.press(OnboardingPresetPack.starter.drafts()[0].userPrompt(at: 0))
                    try await Task.sleep(for: .milliseconds(220))
                    guard let toast = controller.previewError, toast.isVisible else {
                        throw PreviewError.failed("missing toast: \(language) \(zone) \(name)")
                    }
                    precondition(controller.state == .hoverRow || controller.state == .pill)
                    precondition(!toast.canBecomeKey && !toast.isKeyWindow && NSApp.keyWindow === keyWindow)
                    precondition(EdgePreviewProtocol.mode.requestCount == requestCount)
                    let anchor = controller.replyPreviewPanel
                    let expected = BarPlacement.stackedFrame(size: toast.frame.size, gap: 8, zone: zone,
                        anchor: anchor.frame, workArea: OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: anchor.frame)))
                    try verifyFrame(toast.frame, expected: expected, context: "\(language.rawValue) \(zone.rawValue) \(name)")
                    try self.capture(toast, name: "guidance-\(language.rawValue)-\(zone.rawValue)-\(name)")
                    controller.mouseExited()
                    try await Task.sleep(for: .milliseconds(650))
                    precondition(controller.previewError === toast && toast.isVisible)
                    let collapsed = BarPlacement.stackedFrame(size: toast.frame.size, gap: 8, zone: zone,
                        anchor: anchor.frame, workArea: OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: anchor.frame)))
                    try verifyFrame(toast.frame, expected: collapsed, context: "collapsed \(language.rawValue) \(zone.rawValue) \(name)")
                    report.append("PASS: \(language.rawValue) \(zone.rawValue) \(name), no generation/focus change, survives collapse")
                }
            }
        }
        guard let movingToast = controller.previewError else { throw PreviewError.failed("missing moving toast") }
        for zone in SnapZone.allCases {
            controller.prepareReplyPreview(zone: zone)
            try await Task.sleep(for: .milliseconds(250))
            precondition(controller.previewError === movingToast)
            let anchor = controller.replyPreviewPanel
            let expected = BarPlacement.stackedFrame(size: movingToast.frame.size, gap: 8, zone: zone,
                anchor: anchor.frame, workArea: OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: anchor.frame)))
            try verifyFrame(movingToast.frame, expected: expected, context: "live zone change \(zone)")
        }
        report.append("PASS: existing toast follows all four zone changes")
        AppLanguageState.current = .english
        for mode in [CaptureMode.wholeInput, .selection] {
            controller.dismiss()
            controller.prepareReplyPreview(zone: .bottomCenter)
            let count = EdgePreviewProtocol.mode.requestCount
            controller.previewWritingCapture = .success(TextTarget(text: "A draft to polish", captureMode: mode,
                path: mode == .selection ? .clipboard : .ax, writeStrategy: mode == .selection ? .none : .clipboard))
            controller.press(OnboardingPresetPack.starter.drafts()[0].userPrompt(at: 0))
            for _ in 0..<50 {
                if case .result = controller.state { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard case .result = controller.state else {
                throw PreviewError.failed("valid Polish did not generate; state \(controller.state.name), requests \(EdgePreviewProtocol.mode.requestCount - count)")
            }
            precondition(EdgePreviewProtocol.mode.requestCount == count + 1)
            precondition(controller.previewError == nil)
            guard let payload = EdgePreviewProtocol.mode.lastPayload else { throw PreviewError.failed("missing request payload") }
            let events = EdgePreviewAnalytics.events.snapshot.suffix(2)
            precondition(events.count == 2 && events.first == events.last)
            let attempt = events.last!
            precondition(attempt.type == .savedButton && !attempt.isTutorial)
            precondition(payload.rewriteType == "saved_button" && payload.writingStyle == nil)
            precondition(payload.attemptId == attempt.id.uuidString && payload.buttonAnalyticsKey == attempt.buttonAnalyticsKey)
            precondition(payload.prompt == OnboardingPresetPack.starter.drafts()[0].prompt)
            report.append("PASS: actual saved-button payload and start/completion attribution match; style omitted")
            report.append("PASS: nonempty \(mode), exactly one mock rewrite")
        }
        controller.dismiss()
        controller.prepareReplyPreview(zone: .left)
        controller.previewWritingCapture = rejected[0].1
        let count = EdgePreviewProtocol.mode.requestCount
        controller.pressCustomInput()
        try await Task.sleep(for: .milliseconds(300))
        guard case .inputBar(let captured) = controller.state, !captured.target.hasDestination else {
            throw PreviewError.failed("pencil did not open scratch composer")
        }
        precondition(EdgePreviewProtocol.mode.requestCount == count)
        report.append("PASS: pencil opens scratch composer with no rewrite request")
        controller.cancelInput()
        controller.dismiss()
        controller.previewWritingCapture = nil
        try report.joined(separator: "\n").write(to: output.appendingPathComponent("polish-verification.txt"), atomically: true, encoding: .utf8)
    }

    private func render() async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var report: [String] = []
        for language in AppLanguage.allCases {
            AppLanguageState.current = language
            for zone in SnapZone.allCases {
                for kind in 0...2 {
                    controller.configureEdgePreview(context: fixture(kind), zone: zone)
                    try await Task.sleep(for: .milliseconds(180))
                    guard let panel = controller.edgePreviewResult else { continue }
                    try capture(panel, name: "\(language.rawValue)-\(zone.rawValue)-\(kind)")
                    report.append("\(language.rawValue) \(zone.rawValue) \(kind): \(NSStringFromRect(panel.frame))")
                    precondition(panel.frame.height <= (zone == .left || zone == .right ? 520 : 440))
                    precondition(!panel.isMovableByWindowBackground)
                }
                let screen = NSScreen.main!
                let anchor = OverlayPlacement.zoneFrame(zone, barSize: NSSize(width: 44, height: 28), on: screen)
                let geometry = CompanionGeometry(zone: zone, anchor: anchor, screen: screen)
                let panel = GeneratingPanel(geometry: geometry, label: tr("生成中", "Writing…", "生成中"), onCancel: {})
                panel.orderFrontRegardless()
                try await Task.sleep(for: .milliseconds(350))
                try capture(panel, name: "\(language.rawValue)-\(zone.rawValue)-generating")
                precondition(!panel.canBecomeKey && !panel.hasShadow)
                panel.orderOut(nil)
            }
        }
        AppLanguageState.current = .english
        controller.configureEdgePreview(context: fixture(1), zone: .left)
        controller.regenerate()
        try await Task.sleep(for: .milliseconds(500))
        guard case .result(let regenerated) = controller.state else { throw PreviewError.failed("regeneration") }
        precondition(regenerated.count == 2 && regenerated.selectedPage?.pending.instruction == fixture(1).selectedPage?.pending.instruction)
        controller.refine(instruction: "Make it shorter")
        try await Task.sleep(for: .milliseconds(500))
        guard case .result(let refined) = controller.state else { throw PreviewError.failed("refinement") }
        precondition(refined.count == 3 && refined.selectedPage?.pending.instruction.text == "Make it shorter")
        controller.selectResult(offsetBy: -2)
        EdgePreviewProtocol.mode.set("fail")
        controller.regenerate()
        try await Task.sleep(for: .milliseconds(500))
        guard case .result(let restored) = controller.state else { throw PreviewError.failed("failure restoration") }
        precondition(restored.count == 3 && restored.selectedIndex == 0)
        EdgePreviewProtocol.mode.set("slow")
        controller.regenerate()
        try await Task.sleep(for: .milliseconds(60))
        controller.cancelRewrite()
        guard case .result(let cancelled) = controller.state else { throw PreviewError.failed("cancel restoration") }
        precondition(cancelled == restored)
        EdgePreviewProtocol.mode.set("success")
        report.append("PASS: regeneration append, instruction inheritance, refinement, earlier-page selection, failure restoration, cancellation restoration")
        report.append("Accessibility trusted: \(AXPermission.isTrusted)")
        try report.joined(separator: "\n").write(to: output.appendingPathComponent("verification.txt"), atomically: true, encoding: .utf8)
        controller.dismiss()
    }

    private func capture(_ panel: NSPanel, name: String) throws {
        guard let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.bounds.size
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name + ".png"))
    }

    func windowWillClose(_ notification: Notification) {
        controller.dismiss()
        NSApp.terminate(nil)
    }
    private enum PreviewError: Error { case failed(String) }
}

private struct EdgePreviewControls: View {
    let show: (SnapZone, Int, AppLanguage) -> Void
    @State private var zone = SnapZone.left
    @State private var kind = 1
    @State private var language = AppLanguage.english
    var body: some View {
        VStack(spacing: 16) {
            Text("Native edge panels").font(.title2)
            Picker("Position", selection: $zone) {
                ForEach(SnapZone.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Picker("Result", selection: $kind) {
                    Text("Polish").tag(0); Text("Custom").tag(1); Text("Long answer").tag(2); Text("Generating").tag(3)
                }
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            Button("Show panel") { show(zone, kind, language) }
            Text("Local fixtures · mock responses · no account or production requests")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24)
    }
}

private final class EdgePreviewMode: @unchecked Sendable {
    private let lock = NSLock()
    private var value = "success"
    private var requests = 0
    private var payload: RewriteRequest?
    var lastPayload: RewriteRequest? { lock.withLock { payload } }
    func capture(_ request: URLRequest) {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(bytes, count: n) }
        }
        lock.withLock { payload = try? JSONDecoder().decode(RewriteRequest.self, from: data) }
    }
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return requests }
    func recordRequest() { lock.lock(); defer { lock.unlock() }; requests += 1 }
    func set(_ mode: String) { lock.lock(); defer { lock.unlock() }; value = mode }
    func get() -> String { lock.lock(); defer { lock.unlock() }; return value }
}

private final class EdgePreviewProtocol: URLProtocol {
    static let mode = EdgePreviewMode()
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.lastPathComponent == "user_prompts" {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            let buttons = OnboardingPresetPack.starter.drafts().enumerated().map { $0.element.userPrompt(at: $0.offset) }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try! encoder.encode(buttons))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        Self.mode.capture(request)
        Self.mode.recordRequest()
        let mode = Self.mode.get()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let status = mode == "fail" ? 500 : 200
            let text = mode == "fail" ? "{\"error\":\"Preview failure\"}" : "{\"candidates\":[{\"replacement\":\"Thanks for reaching out. Shall we meet next week?\",\"changed\":true}],\"language\":\"en\"}"
            self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: status,
                httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Desktop-Style-Version": "1"])!, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(text.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (mode == "hold" ? 60 : mode == "slow" ? 5 : 0.15), execute: work)
    }
    override func stopLoading() { work?.cancel() }
}

private final class EdgePreviewEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts: [RewriteAttempt] = []
    var snapshot: [RewriteAttempt] { lock.withLock { attempts } }
    func append(_ attempt: RewriteAttempt) { lock.withLock { attempts.append(attempt) } }
}
private struct EdgePreviewAnalytics: Analytics {
    static let events = EdgePreviewEvents()
    func styleApplied(_ style: ResolvedWritingStyle, attemptID: UUID, isTutorial: Bool) {}
    func rewriteStarted(_ attempt: RewriteAttempt, target: TextTarget?) { Self.events.append(attempt) }
    func rewriteCompleted(_ attempt: RewriteAttempt, target: TextTarget, promptOrigin: String?, isReply: Bool, candidateCount: Int, latencyMs: Int) { Self.events.append(attempt) }
    func rewriteFailed(_ attempt: RewriteAttempt, stage: FailureStage, message: String, target: TextTarget?) {}
    func rewriteAbandoned(_ attempt: RewriteAttempt, reason: AbandonReason, target: TextTarget?) {}
    func inserted(_ attempt: RewriteAttempt, target: TextTarget, isReply: Bool, selectedIndex: Int, destination: InsertAction) {}
    func copied(_ attempt: RewriteAttempt, target: TextTarget, isReply: Bool, reason: CopyReason) {}
}
#endif
