import AppKit
import DesktopRewriteKit
import SwiftUI

@MainActor
final class OnboardingIntroContent: ObservableObject {
    @Published var dimOpacity = 0.0
    @Published var pillCopyOpacity = 0.0
    @Published var pillFrame: CGRect = .zero
    let screenFrame: CGRect

    init(screenFrame: CGRect) { self.screenFrame = screenFrame }
}

final class OnboardingIntroPanel: NSPanel {
    var onSkip: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen, content: OnboardingIntroContent) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        let host = NSHostingView(rootView: OnboardingIntroContentView(content: content))
        host.sizingOptions = []
        contentView = host
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onSkip?() } else { super.keyDown(with: event) }
    }
}

private struct OnboardingIntroContentView: View {
    @ObservedObject var content: OnboardingIntroContent

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(content.dimOpacity)
                VStack(spacing: 7) {
                    Text(tr("いつでも、すぐそばに。", "It’ll stay close.", "随时在你身边。")).font(Tokens.LightFont.body(18, weight: .medium))
                    Text(tr("使いやすい画面の端へドラッグ。", "Drag it to a screen edge that suits you.", "拖到顺手的屏幕边缘。")).font(Tokens.LightFont.body(16))
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(width: 300)
                .fixedSize(horizontal: false, vertical: true)
                .position(pillCopyPosition)
                .opacity(content.pillCopyOpacity)
                .accessibilityHidden(content.pillCopyOpacity == 0)
            }
        }
        .ignoresSafeArea()
    }

    private var pillCopyPosition: CGPoint {
        let anchor = IntroGeometry.landingPoint(pill: content.pillFrame, screen: content.screenFrame)
        let side: CGFloat = anchor.y < content.screenFrame.height / 2 ? 80 : -80
        return CGPoint(x: min(max(anchor.x, 166), content.screenFrame.width - 166),
                       y: min(max(anchor.y + side, 48), content.screenFrame.height - 48))
    }
}
