import AppKit
import SwiftUI

/// The window's marks and plates.
///
/// These used to exist to *quarantine* colour: the old system forbade its two accents
/// on buttons, links, badges and focus rings, so every coloured pixel in the window
/// had to be artwork and every piece of artwork had to live in this file. `design.md`
/// puts the accent on the chrome itself, so nothing here is load-bearing any more —
/// it is just the handful of shapes the window draws that are not text or a control.

/// The product mark: the keycap, as line art, in the accent.
///
/// The window gets the outline cut rather than the full-colour app icon. The icon is a
/// two-tone illustration with a black keyline, and at 15 pt on a `#f5f6f7` sidebar it
/// reads as a photograph of something rather than as chrome. Line art in `#5a57ba` is
/// the same rule the rest of §14 follows — the accent is on the chrome. The overlay,
/// which is dark and cannot tint a keyline away, takes the colour cut instead
/// (`BrandGlyph`).
struct AppMark: View {
    var size: CGFloat = 15

    var body: some View {
        Icon(.mark, size: size)
            .foregroundStyle(Tokens.Window.accent)
    }
}

enum MascotAnimation: String, CaseIterable {
    case idle = "MascotIdleSprite"
    case engaged = "MascotEngagedSprite"
    case thinking = "MascotThinkingSprite"
}

/// The product mark in full colour — an off-white keycap with black eyes.
///
/// This is the one image in the app that is not a template. On the overlay's `#141312`
/// the outline cut collapses into a smudge at 16 pt (the keycap's own double keyline
/// closes up), while the filled animation stays legible down to 16 pt at 1x. It is
/// still achromatic, so §8's "the generating capsule is the only colour in the overlay"
/// survives.
struct BrandGlyph: View {
    var size: CGFloat = 16
    var animation: MascotAnimation = .idle

    var body: some View {
        MascotSprite(animation: animation, size: size)
    }
}

/// The collapsed screen-edge pill, reused anywhere the window teaches the gesture.
/// Keeping this as the same shape, mark and dimensions as `PillRootView` means the
/// instruction shows the target instead of naming it with an abstract label.
struct PillPreview: View {
    var scale: CGFloat = 1

    var body: some View {
        BrandGlyph(size: 16 * scale)
            .padding(.horizontal, (Tokens.Geometry.pillCollapsedWidth - 16) * scale / 2)
            .frame(height: Tokens.Geometry.pillHeight * scale)
            .background(
                RoundedRectangle(
                    cornerRadius: Tokens.Overlay.pillRadius * scale,
                    style: .continuous
                )
                .fill(Tokens.Overlay.canvas)
            )
            .shadow(color: .black.opacity(0.22), radius: 6 * scale, y: 2 * scale)
    }
}

/// A deterministic renderer for the 4×4 transparent atlases generated from the mark.
/// The source clips are sampled at 4 fps, which keeps the motion readable at 16 pt and
/// avoids running a video decoder for the app's smallest always-on-screen surface.
struct MascotSprite: View {
    let animation: MascotAnimation
    var size: CGFloat = 16

    var body: some View {
        SpriteSheetView(animation: animation)
            .frame(width: size, height: size)
    }

    static func prewarmFrames() {
        SpriteSheetView.prewarmFrames()
    }
}

private struct SpriteSheetView: NSViewRepresentable {
    let animation: MascotAnimation

    func makeNSView(context: Context) -> SpriteImageView {
        let view = SpriteImageView(frame: .zero)
        view.configure(animation)
        return view
    }

    func updateNSView(_ view: SpriteImageView, context: Context) {
        view.configure(animation)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: SpriteImageView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    static func dismantleNSView(_ view: SpriteImageView, coordinator: ()) {
        view.stopAnimating()
    }

    static func prewarmFrames() {
        SpriteImageView.prewarmFrames()
    }

    final class SpriteImageView: NSView {
        private static let columns = 4
        private static let frameCount = 16
        private static let frameDuration: TimeInterval = 0.25
        private static let frameCache = Dictionary(
            uniqueKeysWithValues: MascotAnimation.allCases.map { animation in
                (animation, loadFrames(named: animation.rawValue))
            }
        )

        private var animation: MascotAnimation?
        private var frames: [NSImage] = []
        private var frameIndex = 0
        private var frameImage: NSImage?
        private var timer: Timer?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard let frameImage else { return }

            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            NSGraphicsContext.current?.imageInterpolation = .high
            frameImage.draw(in: bounds)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopAnimating()
            } else {
                startAnimating()
            }
        }

        func configure(_ animation: MascotAnimation) {
            guard self.animation != animation else { return }
            self.animation = animation
            frames = Self.frameCache[animation] ?? []
            frameIndex = 0
            frameImage = frames.first
            needsDisplay = true
            if window != nil { startAnimating() }
        }

        func stopAnimating() {
            timer?.invalidate()
            timer = nil
        }

        static func prewarmFrames() {
            _ = frameCache
        }

        private func startAnimating() {
            guard timer == nil, frames.count > 1 else { return }
            let timer = Timer(
                timeInterval: Self.frameDuration,
                target: self,
                selector: #selector(advanceFrame),
                userInfo: nil,
                repeats: true
            )
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        @objc private func advanceFrame() {
            guard !frames.isEmpty else { return }
            frameIndex = (frameIndex + 1) % frames.count
            frameImage = frames[frameIndex]
            needsDisplay = true
        }

        private static func loadFrames(named assetName: String) -> [NSImage] {
            guard let sheet = NSImage(named: NSImage.Name(assetName)),
                  let image = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else { return [] }

            let frameWidth = image.width / columns
            let rows = frameCount / columns
            let frameHeight = image.height / rows

            return (0..<frameCount).compactMap { index in
                let crop = CGRect(
                    x: CGFloat((index % columns) * frameWidth),
                    y: CGFloat((index / columns) * frameHeight),
                    width: CGFloat(frameWidth),
                    height: CGFloat(frameHeight)
                )
                guard let frame = image.cropping(to: crop) else { return nil }
                return NSImage(
                    cgImage: frame,
                    size: NSSize(width: CGFloat(frameWidth), height: CGFloat(frameHeight))
                )
            }
        }
    }
}

/// Identity, in the sidebar and on the account page. A flat accent disc with the
/// initial knocked out in white.
struct Avatar: View {
    let initial: String
    var diameter: CGFloat = 30

    var body: some View {
        Circle()
            .fill(Tokens.Window.accent)
            .frame(width: diameter, height: diameter)
            .overlay(
                Text(initial)
                    .font(Tokens.Font.body(diameter * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

/// A glyph on a tinted disc — `design.md`'s app-integration plates, and what an
/// empty state leads with here.
struct IconPlate: View {
    let icon: Icon.Name
    var diameter: CGFloat = 36
    var tinted = true

    var body: some View {
        Circle()
            .fill(tinted ? Tokens.Window.accentTint : Tokens.Window.surface)
            .frame(width: diameter, height: diameter)
            .overlay(
                Icon(icon, size: diameter * 0.46)
                    .foregroundStyle(tinted ? Tokens.Window.accent : Tokens.Window.textSecondary)
            )
    }
}

/// A real application icon, by bundle id.
///
/// `design.md`'s home page leads with the icons of the apps you dictate into; ours
/// shows the apps you have actually rewritten in, which is the same claim backed by
/// the local history. Falls back to a plate for an app that has since been removed.
struct AppIconView: View {
    let bundleId: String
    var size: CGFloat = 22

    var body: some View {
        if let icon = Self.icon(for: bundleId) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: size, height: size)
        } else {
            IconPlate(icon: .window, diameter: size, tinted: false)
        }
    }

    private static var cache: [String: NSImage?] = [:]

    private static func icon(for bundleId: String) -> NSImage? {
        if let cached = cache[bundleId] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
        cache[bundleId] = icon
        return icon
    }
}
