#if DEBUG
import AppKit
import DesktopRewriteKit
import SwiftUI

@MainActor enum WhatsNewPreview {
    static var isRunning: Bool { renders || ProcessInfo.processInfo.arguments.contains("--preview-whats-new") }
    static var renders: Bool { ProcessInfo.processInfo.arguments.contains("--render-whats-new") }
    private static var window: NSWindow?

    static func show() {
        AppLanguageState.current = .english
        let preview = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        preview.title = "What's new — isolated preview"
        preview.appearance = NSAppearance(named: .aqua)
        preview.isReleasedWhenClosed = false
        preview.contentView = NSHostingView(rootView: InteractiveReleasePreview())
        preview.center()
        window = preview
        preview.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func render() async throws {
        let output = URL(fileURLWithPath: "/private/tmp/keigo-whats-new-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for language in AppLanguage.allCases {
            AppLanguageState.current = language
            for page in ReleaseHighlights.features.indices {
                for step in 0...1 {
                    try await capture(WhatsNewCard(version: "preview", initialPage: page, initialDemoStep: step,
                                                  onDismiss: {}, onOpenButtons: {}),
                                      name: "\(language.rawValue)-\(ReleaseHighlights.features[page].rawValue)-\(step)",
                                      output: output)
                }
            }
        }
    }

    private static func capture<V: View>(_ view: V, name: String, output: URL) async throws {
        let size = NSSize(width: 920, height: 640)
        let host = NSHostingView(rootView: ZStack {
            Tokens.Window.environment
            view
        }.frame(width: size.width, height: size.height))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1840, pixelsHigh: 1280,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { throw CocoaError(.fileWriteUnknown) }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: output.appendingPathComponent(name + ".png"))
        window.contentView = nil
        window.close()
    }
}

private struct InteractiveReleasePreview: View {
    @State private var language = AppLanguage.english
    @State private var presented = true
    @State private var destination = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.endonym).tag($0) }
                }.frame(width: 200)
                Spacer()
            }.padding(12)
            ZStack {
                Tokens.Window.environment
                VStack(spacing: 16) {
                    Text(destination)
                    Button("Reopen preview") { presented = true }
                }.disabled(presented).accessibilityHidden(presented)
                if presented {
                    WhatsNewModal(version: "preview", onDismiss: {
                        destination = "Dismissed"; presented = false
                    }, onOpenButtons: {
                        destination = "Buttons destination selected"; presented = false
                    })
                    .id(language)
                }
            }
        }
        .onChange(of: language) { _, value in AppLanguageState.current = value }
    }
}
#endif
