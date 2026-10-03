#if DEBUG
import AppKit
import SwiftUI
import DesktopRewriteKit
import TextIO

private final class ResearchTriggerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class VisualIntentResearch: NSObject, ObservableObject {
    @Published var message = "Setup: Accessibility and Screen Recording are required. Each capture sends the marked window and your rough intention to the research model. Use plain message bodies without signatures. Results are preview-only."
    @Published var busy = false
    @Published var request: VisualIntentRequest?
    @Published var response: VisualIntentResponse?
    @Published var image: NSImage?
    @Published var sendToModel = true
    @Published var setupStatus = "Checking permissions and account…"
    private let ax = AXTextIO()
    private let auth: AuthService
    private let service: DesktopRewriteService
    private var trigger: NSPanel?
    private var preview: NSWindow?
    private var capture: VisualIntentCapture?
    private var task: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var activationEpoch = 0
    private var attempt = UUID()

    init(config: SupabaseConfig, auth: AuthService) {
        self.auth = auth
        service = DesktopRewriteService(config: config, auth: auth)
        super.init()
    }

    func show() {
        let panel = ResearchTriggerPanel(contentRect: CGRect(x: 30, y: 120, width: 156, height: 42),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        let button = NSButton(title: "A · Capture intent", target: self, action: #selector(press))
        button.bezelStyle = .rounded
        panel.contentView = button
        trigger = panel
        panel.orderFrontRegardless()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.activationEpoch += 1 }
        }
        showPreview()
        refreshSetupStatus()
    }

    func refreshSetupStatus() {
        let permissions = "Accessibility: \(AXPermission.isTrusted ? "enabled" : "needed") · Screen Recording: \(CGPreflightScreenCaptureAccess() ? "enabled" : "needed")"
        Task { @MainActor in
            let email = await auth.currentEmail ?? "not signed in — use the normal app to sign in first"
            setupStatus = "\(permissions) · Account: \(email)"
        }
    }

    func permissions() {
        _ = AXPermission.requestTrust()
        _ = CGRequestScreenCaptureAccess()
        refreshSetupStatus()
        message = "After granting both permissions, relaunch if macOS asks. Close this window, focus a message body, type rough intent, then press A · Capture intent."
    }

    @objc private func press() {
        guard !busy else { return }
        guard let host = NSWorkspace.shared.frontmostApplication,
              host.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            message = "No external message field is focused. Close this research window, click the message body in your app, type your rough intention there, then press the floating A button."
            showPreview()
            return
        }
        let pid = host.processIdentifier
        let epoch = activationEpoch
        let id = UUID(); attempt = id
        busy = true; response = nil; request = nil; image = nil; capture = nil
        message = "Capturing the focused message field. Keep its text, conversation and window unchanged until the preview appears."
        task = Task { @MainActor in
            defer { if attempt == id { busy = false } }
            do {
                let result = try await VisualIntentCapture.take(ax: ax, pid: pid) { self.activationEpoch == epoch }
                try Task.checkCancellation()
                guard attempt == id else { return }
                capture = result; request = result.request
                image = NSImage(data: result.markedPNG)
                message = "Captured in \(result.captureMs) ms. Magenta = frozen composer. Verify its position before scoring."
                showPreview()
                if sendToModel { try await generate(result.request, id: id) }
            } catch {
                guard attempt == id else { return }
                message = Self.errorMessage(error)
                showPreview()
            }
        }
    }

    func cancel() {
        attempt = UUID(); task?.cancel(); task = nil; busy = false
        message = "Cancelled. Nothing was inserted."
    }

    func replay() {
        guard !busy, let request else { return }
        let id = UUID(); attempt = id; busy = true; response = nil
        task = Task { @MainActor in
            defer { if attempt == id { busy = false } }
            do { try await generate(request, id: id) }
            catch { if attempt == id { message = Self.errorMessage(error) } }
        }
    }

    private func generate(_ request: VisualIntentRequest, id: UUID) async throws {
        let account = await auth.currentSession?.userId
        let start = Date()
        message = "Running the research model… The draft will appear here when the request finishes."
        let result = try await service.visualIntent(request)
        try Task.checkCancellation()
        guard attempt == id, account != nil, await auth.currentSession?.userId == account else { return }
        response = result
        message = "\(result.result.status.rawValue) · \(result.model) · reasoning \(result.reasoningEffort ?? "unreported") · \(result.promptVersion) · model \(result.modelMs) ms · request \(Int(Date().timeIntervalSince(start) * 1000)) ms. Cyan = model's claimed conversation; these claims require human verification."
        if let warnings = result.geometryWarnings, !warnings.isEmpty {
            message += " \(warnings.count) geometry warning(s); draft retained for evaluation."
        }
    }

    private static func errorMessage(_ error: Error) -> String {
        switch error {
        case RewriteError.notSignedIn: return "Sign in using the normal KeigoButton app, then run A again."
        case RewriteError.backend(let message): return message
        case RewriteError.invalidResponse: return "The server response failed capture correlation or grounding validation."
        case TextIOError.notTrusted: return "Accessibility permission is required for this research build. Use Permission setup."
        default: return error.localizedDescription
        }
    }

    func loadReplay() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 12_000_000 else { throw RewriteError.invalidResponse }
            let saved = try JSONDecoder().decode(VisualIntentRequest.self, from: data)
            try saved.validate()
            guard saved.composerBox.fits(width: saved.imageWidth, height: saved.imageHeight),
                  let bytes = Data(base64Encoded: saved.imageBase64), let decoded = NSImage(data: bytes) else {
                throw RewriteError.invalidResponse
            }
            capture = nil; request = saved; response = nil; image = decoded
            message = "Loaded an immutable capture. Run A to make a fresh, independent model request."
        } catch { message = error.localizedDescription }
    }

    func export() {
        guard let request else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.prompt = "Export capture here"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let folder = directory.appendingPathComponent("visual-intent-\(request.captureId)-\(UUID().uuidString.prefix(8))")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(request).write(to: folder.appendingPathComponent("request.json"), options: .atomic)
            if let response { try encoder.encode(response).write(to: folder.appendingPathComponent("response.json"), options: .atomic) }
            if let capture {
                try capture.originalPNG.write(to: folder.appendingPathComponent("original.png"), options: .atomic)
                try capture.markedPNG.write(to: folder.appendingPathComponent("marked.png"), options: .atomic)
                let meta: [String: Any] = ["captureMs": capture.captureMs, "windowID": capture.windowID, "outcome": message,
                    "applicationPID": capture.snapshot.applicationPID, "focusedPID": capture.snapshot.target.element?.pid ?? 0,
                    "capturedAt": ISO8601DateFormatter().string(from: capture.snapshot.capturedAt),
                    "pixelScale": capture.pixelScale, "focusSubscriptions": capture.focusSubscriptions,
                    "frameMetadata": capture.frameMetadata,
                    "windowBounds": NSStringFromRect(capture.snapshot.windowFrame),
                    "composerBounds": NSStringFromRect(capture.snapshot.composerFrame), "imageBytes": Data(base64Encoded: request.imageBase64)?.count ?? 0]
                try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
                    .write(to: folder.appendingPathComponent("capture.json"), options: .atomic)
            }
            message = "Exported to \(folder.path). This folder contains the visible conversation and rough intent."
        } catch { message = error.localizedDescription }
    }

    private func showPreview() {
        if preview == nil {
            let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 1100, height: 760),
                                  styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "KeigoButton · Visual intent A research"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: VisualIntentResearchView(model: self))
            preview = window
        }
        preview?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct VisualIntentResearchView: View {
    @ObservedObject var model: VisualIntentResearch
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.setupStatus).font(.caption).textSelection(.enabled)
            Text(model.message).textSelection(.enabled)
            HStack {
                Button("Permission setup") { model.permissions() }.disabled(model.busy)
                Button("Recheck") { model.refreshSetupStatus() }.disabled(model.busy)
                Toggle("Send each new capture to model", isOn: $model.sendToModel).disabled(model.busy)
                Button("Load capture") { model.loadReplay() }.disabled(model.busy)
                Button("Run A again") { model.replay() }.disabled(model.busy || model.request == nil)
                Button("Export") { model.export() }.disabled(model.busy || model.request == nil)
                if model.busy { ProgressView().controlSize(.small); Button("Cancel") { model.cancel() } }
                Spacer()
                Button("Quit research") { NSApp.terminate(nil) }
            }
            if let image = model.image, let request = model.request {
                HSplitView {
                    GeometryReader { g in
                        let scale = min(g.size.width / Double(request.imageWidth), g.size.height / Double(request.imageHeight))
                        ZStack(alignment: .topLeading) {
                            Image(nsImage: image).resizable().frame(width: Double(request.imageWidth) * scale, height: Double(request.imageHeight) * scale)
                            ForEach(Array((model.response?.result.conversationRegion ?? []).enumerated()), id: \.offset) { _, region in
                                Rectangle().stroke(.cyan, lineWidth: 2)
                                    .frame(width: region.box.width * scale, height: region.box.height * scale)
                                    .offset(x: region.box.x * scale, y: region.box.y * scale)
                            }
                        }
                    }.frame(minWidth: 550, minHeight: 500)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Rough intent").bold(); Text(request.intent)
                            if let result = model.response?.result {
                                Text("Draft").bold(); Text(result.draft ?? "No grounded draft available.")
                                Text("Claimed evidence").bold()
                                ForEach(Array(result.evidence.enumerated()), id: \.offset) { _, e in
                                    Text("\(e.author ?? "Unknown author"): \(e.excerpt)\(e.partial ? " [partial]" : "")")
                                }
                                ForEach(result.missingContext, id: \.self) { Text($0).foregroundStyle(.orange) }
                                if let warnings = model.response?.geometryWarnings, !warnings.isEmpty {
                                    Text("Geometry diagnostics").bold()
                                    ForEach(warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
                                }
                            }
                        }.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                    }.frame(minWidth: 300)
                }
            } else { Spacer(); Text("Close this window and use the floating A button from Gmail, Slack or LinkedIn."); Spacer() }
        }.padding(16).frame(minWidth: 950, minHeight: 620)
    }
}
#endif
