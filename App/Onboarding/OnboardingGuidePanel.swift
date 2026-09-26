import AppKit
import DesktopRewriteKit
import SwiftUI

// Actual controls report geometry; labels and translations never determine an arrow's target.
enum LessonAnchor: Hashable { case bar, polish, custom, reply, composer, result }

final class WeakLessonAnchor {
    weak var view: NSView?
    init(_ view: NSView) { self.view = view }
}

struct LessonAnchorReader: NSViewRepresentable {
    let anchor: LessonAnchor
    let controller: OverlayController

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.anchor = anchor
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.controller = controller
        nsView.anchor = anchor
        nsView.report()
    }

    final class AnchorView: NSView {
        var anchor: LessonAnchor = .bar
        weak var controller: OverlayController?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        override func layout() { super.layout(); report() }
        func report() {
            guard window != nil else { return }
            controller?.lessonAnchors[anchor] = WeakLessonAnchor(self)
            // SwiftUI may be installing this view during a state update.
            DispatchQueue.main.async { [weak controller] in controller?.syncLessonGuide() }
        }
    }
}

@MainActor
final class OnboardingGuidePanel: NSPanel {
    private weak var controller: OverlayController?
    private var lastPresentation: Presentation?
    private struct Presentation: Equatable {
        let label: String
        let edge: OnboardingGuidePlacement.Edge
        let size: CGSize
        let tip: CGFloat
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(controller: OverlayController) {
        self.controller = controller
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSApplication.didChangeScreenParametersNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: name, object: nil)
        }
    }

    override func close() {
        NotificationCenter.default.removeObserver(self)
        super.close()
    }

    @objc private func windowChanged(_ notification: Notification) {
        guard notification.object as? NSWindow !== self else { return }
        refresh()
    }

    func refresh() {
        guard let controller, controller.lessonGuideCanShow, let lesson = controller.lesson,
              let anchor = lesson.guideAnchor, let target = controller.lessonAnchorFrame(anchor) else {
            orderOut(nil)
            return
        }
        let owner = anchor == .bar ? controller.lessonBarFrame
            : controller.lessonAnchors[anchor]?.view?.window?.frame ?? target
        let screen = OverlayPlacement.screen(containing: owner)
        let preferred: OnboardingGuidePlacement.Edge
        switch controller.parkedZone {
        case .bottomCenter: preferred = .above
        case .topCenter: preferred = .below
        case .left: preferred = .right
        case .right: preferred = .left
        }
        let label = lesson.phase == .hover
            ? tr("ここから始めましょう", "Start here", "从这里开始")
            : lesson.instruction(copyOnly: controller.insertAction == .copyOnly)
        let size = GuideCard.fittingSize(for: label)
        guard let placement = OnboardingGuidePlacement.place(target: target, owner: owner,
                size: size, workArea: OverlayPlacement.workArea(on: screen),
                preferred: preferred, obstacles: controller.lessonGuideObstacles) else {
            orderOut(nil)
            return
        }
        let tip: CGFloat
        switch placement.edge {
        case .above, .below: tip = min(max(target.midX - placement.frame.minX, 28), size.width - 28)
        case .left, .right: tip = min(max(placement.frame.maxY - target.midY, 28), size.height - 28)
        }
        let presentation = Presentation(label: label, edge: placement.edge,
                                        size: size, tip: tip)
        if presentation != lastPresentation {
            let hosting = NSHostingView(rootView: GuideCard(label: label, edge: placement.edge,
                                                          size: size, tip: tip))
            hosting.sizingOptions = []
            contentView = hosting
            lastPresentation = presentation
        }
        if frame != placement.frame { setFrame(placement.frame, display: true) }
        if !isVisible { orderFrontRegardless() }
    }
}

/// Quiet light-window typography in a small native-style callout. The panel remains
/// mouse-transparent; instruction changes never take focus away from the real control.
private struct GuideCard: View {
    let label: String
    let edge: OnboardingGuidePlacement.Edge
    let size: CGSize
    let tip: CGFloat

    static func fittingSize(for label: String) -> CGSize {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.alignment = .center
        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 16), .paragraphStyle: paragraph
        ])
        let textWidth = min(268, max(108, ceil(text.size().width)))
        let bounds = text.boundingRect(with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        // 10 pt shadow/pointer gutter, then 16 horizontal / 12 vertical text insets.
        return CGSize(width: textWidth + 52, height: max(64, ceil(bounds.height) + 44))
    }

    var body: some View {
        Text(label)
            .font(Tokens.LightFont.Onboarding.body)
            .foregroundStyle(Tokens.Window.textPrimary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .frame(width: size.width, height: size.height)
            .background {
                GuideBubble(edge: edge, tip: tip)
                    .fill(Tokens.Window.surface)
                    .shadow(color: .black.opacity(0.10), radius: 5, y: 2)
                    .overlay {
                        GuideBubble(edge: edge, tip: tip)
                            .stroke(Tokens.Window.borderControl, lineWidth: 0.5)
                    }
            }
            .accessibilityHidden(true)
    }
}

/// A single outline keeps the small pointer joined to the surface without a seam.
private struct GuideBubble: Shape {
    let edge: OnboardingGuidePlacement.Edge
    let tip: CGFloat

    func path(in rect: CGRect) -> Path {
        let box = rect.insetBy(dx: 10, dy: 10)
        let radius: CGFloat = 10
        let halfPointer: CGFloat = 5
        let depth: CGFloat = 6
        return Path { p in
            p.move(to: CGPoint(x: box.minX + radius, y: box.minY))
            if edge == .below {
                p.addLine(to: CGPoint(x: tip - halfPointer, y: box.minY))
                p.addLine(to: CGPoint(x: tip, y: box.minY - depth))
                p.addLine(to: CGPoint(x: tip + halfPointer, y: box.minY))
            }
            p.addLine(to: CGPoint(x: box.maxX - radius, y: box.minY))
            p.addQuadCurve(to: CGPoint(x: box.maxX, y: box.minY + radius), control: CGPoint(x: box.maxX, y: box.minY))
            if edge == .left {
                p.addLine(to: CGPoint(x: box.maxX, y: tip - halfPointer))
                p.addLine(to: CGPoint(x: box.maxX + depth, y: tip))
                p.addLine(to: CGPoint(x: box.maxX, y: tip + halfPointer))
            }
            p.addLine(to: CGPoint(x: box.maxX, y: box.maxY - radius))
            p.addQuadCurve(to: CGPoint(x: box.maxX - radius, y: box.maxY), control: CGPoint(x: box.maxX, y: box.maxY))
            if edge == .above {
                p.addLine(to: CGPoint(x: tip + halfPointer, y: box.maxY))
                p.addLine(to: CGPoint(x: tip, y: box.maxY + depth))
                p.addLine(to: CGPoint(x: tip - halfPointer, y: box.maxY))
            }
            p.addLine(to: CGPoint(x: box.minX + radius, y: box.maxY))
            p.addQuadCurve(to: CGPoint(x: box.minX, y: box.maxY - radius), control: CGPoint(x: box.minX, y: box.maxY))
            if edge == .right {
                p.addLine(to: CGPoint(x: box.minX, y: tip + halfPointer))
                p.addLine(to: CGPoint(x: box.minX - depth, y: tip))
                p.addLine(to: CGPoint(x: box.minX, y: tip - halfPointer))
            }
            p.addLine(to: CGPoint(x: box.minX, y: box.minY + radius))
            p.addQuadCurve(to: CGPoint(x: box.minX + radius, y: box.minY), control: CGPoint(x: box.minX, y: box.minY))
            p.closeSubpath()
        }
    }
}
