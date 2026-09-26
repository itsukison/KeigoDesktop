#if DEBUG
import AppKit
import DesktopRewriteKit
import SwiftUI

@MainActor final class BarMaterialPreview: NSObject, NSWindowDelegate {
    static var isRunning: Bool { ProcessInfo.processInfo.arguments.contains("--preview-smoked-bar") }
    private static var retained: BarMaterialPreview?
    private let window: NSWindow
    private var panels: [NSPanel] = []
    private var reducedMotion = false
    private var opaque = false

    static func show() {
        retained = BarMaterialPreview()
        retained?.window.makeKeyAndOrderFront(nil)
        retained?.refresh()
        NSApp.activate(ignoringOtherApps: true)
    }

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 420),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Smoked glass — native test"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: PreviewBackdrop { [weak self] motion, opaque in
            self?.reducedMotion = motion
            self?.opaque = opaque
            self?.refresh()
        })
    }

    private func refresh() {
        for panel in panels { window.removeChildWindow(panel); panel.orderOut(nil) }
        panels.removeAll()
        let origin = window.convertToScreen(NSRect(origin: .zero, size: .zero)).origin
        func present<V: View>(_ view: V, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            let panel = PillPanel(contentRect: NSRect(x: origin.x + x - width / 2, y: origin.y + y, width: width, height: height))
            let host = NSHostingView(rootView: view.frame(width: width, height: height))
            host.sizingOptions = []
            panel.contentView = host
            window.addChildWindow(panel, ordered: .above)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        present(ZStack {
            SmokedGlassSurface(shape: Capsule(), forceOpaque: opaque)
            BrandGlyph(size: 16, isAnimating: !reducedMotion)
        }, x: 150, y: 207, width: 44, height: 28)
        present(ZStack {
            SmokedGlassSurface(shape: Capsule(), forceOpaque: opaque)
            HStack(spacing: 8) {
                BrandGlyph(size: 16, isAnimating: !reducedMotion)
                RowPill(title: "Polish") { [weak self] in self?.refresh() }
                RowPill(systemImage: "pencil") {}
            }.padding(.horizontal, 12)
        }, x: 380, y: 204, width: 158, height: 34)

        let anchor = NSRect(x: origin.x + 588, y: origin.y + 203, width: 44, height: 28)
        let geometry = CompanionGeometry(zone: .bottomCenter, anchor: anchor, screen: OverlayPlacement.screen(containing: anchor))
        let generating = GeneratingPanel(geometry: geometry, label: "Writing…") { [weak self] in
            self?.panels.last?.orderOut(nil)
        }
        generating.contentView = NSHostingView(rootView: GeneratingCapsule(label: "Writing…", forceReducedMotion: reducedMotion, forceOpaque: opaque) { [weak self] in
            self?.panels.last?.orderOut(nil)
        })
        generating.setFrameOrigin(NSPoint(x: origin.x + 610 - generating.frame.width / 2,
                                         y: origin.y + 203 - Tokens.Geometry.generatingGlowPadding))
        window.addChildWindow(generating, ordered: .above)
        generating.orderFrontRegardless()
        panels.append(generating)
    }

    func windowWillClose(_ notification: Notification) {
        panels.forEach { $0.orderOut(nil) }
        NSApp.terminate(nil)
    }
}

private struct PreviewBackdrop: View {
    let onChange: (Bool, Bool) -> Void
    @State private var background = 0
    @State private var reducedMotion = false
    @State private var opaque = false

    var body: some View {
        ZStack {
            if background == 0 {
                LinearGradient(colors: [Color(hex: 0xadc9d1), Color(hex: 0x577c8d), Color(hex: 0xddc2a1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                (background == 1 ? Color(hex: 0xf6f8fa) : Color(hex: 0x17212c))
            }
            Canvas { context, size in
                for x in stride(from: CGFloat(0), to: size.width, by: 12) {
                    let rect = CGRect(x: x, y: 174, width: 2, height: 80)
                    context.fill(Path(rect), with: .color((background == 2 ? Color.white : .black).opacity(0.35)))
                }
                for y in stride(from: CGFloat(182), through: 242, by: 20) {
                    context.draw(Text("Background detail · ABC 123 · 背景の文字 · ABC 123 · Background detail")
                        .font(.system(size: 14)).foregroundStyle(background == 2 ? .white : .black),
                        at: CGPoint(x: size.width / 2, y: y))
                }
            }.allowsHitTesting(false)
            VStack(spacing: 16) {
                Text("Smoked glass + BorderBeam").font(.system(size: 22, weight: .medium))
                HStack {
                    Picker("Background", selection: $background) {
                        Text("Desktop colors").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }.pickerStyle(.segmented).frame(width: 320)
                    Button("Restart") { onChange(reducedMotion, opaque) }
                }
                HStack {
                    Text("Resting").frame(width: 230)
                    Text("Expanded").frame(width: 230)
                    Text("Generating").frame(width: 230)
                }.font(.system(size: 12)).padding(.top, 16)
                Spacer()
                HStack(spacing: 20) {
                    Toggle("Reduce motion", isOn: $reducedMotion)
                    Toggle("Opaque fallback", isOn: $opaque)
                }.toggleStyle(.checkbox)
                Text("Native surfaces · preview only · no text is captured or sent")
                    .font(.system(size: 12))
            }
            .foregroundStyle(background == 2 ? .white : Color(hex: 0x17212c))
            .padding(32)
        }
        .frame(width: 760, height: 420)
        .environment(\.colorScheme, background == 2 ? .dark : .light)
        .onChange(of: reducedMotion) { _, _ in onChange(reducedMotion, opaque) }
        .onChange(of: opaque) { _, _ in onChange(reducedMotion, opaque) }
    }
}
#endif
