import AppKit
import AVFoundation
import DesktopRewriteKit
import SwiftUI

enum IntroCharacterState {
    case intro, bounce, look, fall, land, idle
}

@MainActor
final class IntroPillPresentation: ObservableObject {
    let canvasSize: CGSize
    let reduceMotion: Bool
    @Published var position: CGPoint
    @Published var characterSize: CGFloat = 140
    @Published var scale: CGSize = CGSize(width: 0.96, height: 0.96)
    @Published var opacity: Double = 0
    @Published var copyOpacity: Double = 0
    @Published var supportingCopyOpacity: Double = 1
    @Published var showsSecondCopy = false
    @Published var travelProgress: CGFloat = 0
    @Published var pillWidth: CGFloat = 0
    @Published var pillOpacity: Double = 0
    @Published var spriteMix: Double = 0
    @Published var characterState: IntroCharacterState = .intro

    init(canvasSize: CGSize, reduceMotion: Bool) {
        self.canvasSize = canvasSize
        self.reduceMotion = reduceMotion
        position = .zero
        if reduceMotion { scale = CGSize(width: 1, height: 1) }
    }
}

private struct IntroCharacterAnchor: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct IntroPillView: View {
    @ObservedObject var presentation: IntroPillPresentation

    var body: some View {
        VStack(spacing: 24) {
            Color.clear
                .frame(width: 140, height: 140)
                .anchorPreference(key: IntroCharacterAnchor.self, value: .bounds) { $0 }
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text(tr("KeigoButtonへようこそ。", "Meet KeigoButton.", "认识一下 KeigoButton。"))
                    .font(Tokens.LightFont.body(32))
                    .tracking(Tokens.LightFont.displayTracking(32))
                ZStack(alignment: .top) {
                    Text(tr("伝えたい気持ちを、\n伝わる言葉に。", "A small layer between what you mean\nand what you send.", "让心中所想，\n成为恰当的表达。"))
                        .opacity(presentation.showsSecondCopy ? 0 : presentation.supportingCopyOpacity)
                        .accessibilityHidden(presentation.showsSecondCopy || presentation.supportingCopyOpacity == 0)
                    Text(tr("今書いている場所で、思いついた言葉を\nその場に合う表現に整えます。", "It turns rough intent into words that fit the moment, right where you’re typing.", "就在你输入的地方，\n把初步想法整理成适合当下的表达。"))
                        .opacity(presentation.showsSecondCopy ? presentation.supportingCopyOpacity : 0)
                        .accessibilityHidden(!presentation.showsSecondCopy || presentation.supportingCopyOpacity == 0)
                }
                    .font(Tokens.LightFont.body(20))
                    .lineSpacing(5)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .opacity(presentation.copyOpacity)
            .accessibilityHidden(presentation.copyOpacity == 0)
        }
        .frame(width: min(460, presentation.canvasSize.width - 64))
        .fixedSize(horizontal: false, vertical: true)
        .position(x: presentation.canvasSize.width / 2, y: presentation.canvasSize.height * 0.45)
        .frame(width: presentation.canvasSize.width, height: presentation.canvasSize.height)
        .overlayPreferenceValue(IntroCharacterAnchor.self) { anchor in
            GeometryReader { geometry in
                if let anchor {
                    let slot = geometry[anchor]
                    let progress = presentation.travelProgress
                    let position = CGPoint(
                        x: slot.midX + (presentation.position.x - slot.midX) * progress,
                        y: slot.midY + (presentation.position.y - slot.midY) * progress
                    )
                    ZStack {
                        SmokedGlassSurface(shape: RoundedRectangle(
                            cornerRadius: Tokens.Overlay.pillRadius, style: .continuous
                        ))
                            .frame(width: presentation.pillWidth, height: Tokens.Geometry.pillHeight)
                            .opacity(presentation.pillOpacity)
                        IntroCharacterView(state: presentation.characterState,
                                           reduceMotion: presentation.reduceMotion,
                                           spriteMix: presentation.spriteMix)
                            .frame(width: presentation.characterSize, height: presentation.characterSize)
                            .scaleEffect(x: presentation.scale.width, y: presentation.scale.height)
                            .opacity(presentation.opacity)
                    }
                    .position(position)
                    .accessibilityHidden(true)
                }
            }
        }
    }
}

/// Only internal expression belongs here; the native presentation owns all geometry.
struct IntroCharacterView: View {
    let state: IntroCharacterState
    let reduceMotion: Bool
    let spriteMix: Double

    var body: some View {
        GeometryReader { geometry in
            // Resting alpha bounds end at y = 0.839 in both assets. Align that edge
            // with the slot; the movie's small bounce can overflow without clipping.
            let sourceSide = geometry.size.width / 0.722
            Group {
                if !reduceMotion,
                   let url = Bundle.main.url(forResource: "OnboardingMascotLoop", withExtension: "mov") {
                    IntroExpressionView(url: url, playing: state == .look)
                } else {
                    Image("MascotPortrait").resizable().scaledToFit()
                }
            }
            .frame(width: sourceSide, height: sourceSide)
            .position(x: geometry.size.width / 2 + (0.5 - 0.517) * sourceSide,
                      y: geometry.size.height / 2 + (0.5 - 0.478) * sourceSide)
        }
        .opacity(1 - spriteMix)
        .overlay {
            GeometryReader { geometry in
                BrandGlyph(size: geometry.size.width, isAnimating: false)
                    .opacity(spriteMix)
            }
        }
    }
}

private struct IntroExpressionView: NSViewRepresentable {
    let url: URL
    let playing: Bool

    func makeNSView(context: Context) -> ExpressionPlayer {
        let view = ExpressionPlayer(url: url)
        view.setPlaying(playing)
        return view
    }

    func updateNSView(_ nsView: ExpressionPlayer, context: Context) {
        nsView.setPlaying(playing)
    }

    static func dismantleNSView(_ nsView: ExpressionPlayer, coordinator: ()) {
        nsView.player.pause()
    }

    final class ExpressionPlayer: NSView {
        let player: AVPlayer
        private let video = AVPlayerLayer()
        private let poster = CALayer()
        private var readyObservation: NSKeyValueObservation?
        private var hasPlayed = false
        private var showingVideo = false

        init(url: URL) {
            player = AVPlayer(url: url)
            super.init(frame: .zero)
            wantsLayer = true
            poster.contents = NSImage(named: "MascotPortrait")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            poster.contentsGravity = .resizeAspect
            layer?.addSublayer(poster)
            video.player = player
            video.videoGravity = .resizeAspect
            video.opacity = 0
            layer?.addSublayer(video)
            player.isMuted = true
            readyObservation = video.observe(\.isReadyForDisplay, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.revealReadyVideo() }
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        func setPlaying(_ playing: Bool) {
            if playing {
                hasPlayed = true
                player.play()
                revealReadyVideo()
            } else {
                player.pause()
            }
        }

        private func revealReadyVideo() {
            guard hasPlayed, video.isReadyForDisplay, !showingVideo else { return }
            showingVideo = true
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.18)
            video.opacity = 1
            poster.opacity = 0
            CATransaction.commit()
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            video.frame = bounds
            poster.frame = bounds
            CATransaction.commit()
        }
    }
}
