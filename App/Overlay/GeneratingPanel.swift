import AppKit
import SwiftUI

/// A separate window from the pill, per `generating.png` and §4's window table.
/// Never key — the user should be able to keep typing while a rewrite is in flight.
final class GeneratingPanel: NSPanel {

    init(anchor: NSRect, label: String, onCancel: @escaping () -> Void) {
        let glow = Tokens.Geometry.generatingGlowPadding
        let spread = Tokens.Geometry.generatingGlowSpread
        let size = NSSize(
            width: Tokens.Geometry.generatingCapsuleWidth + spread * 2,
            height: Tokens.Geometry.generatingCapsuleHeight + spread + glow
        )
        // Takes the bar's place rather than stacking above it, per `generating.png`.
        // The bar is hidden for the duration, so the anchor the user's eye is tracking
        // does not move — it just changes state.
        //
        // The anchor is dropped by the glow padding so it is the **capsule's** bottom
        // edge that lands on the bar's line rather than the window's; the padding hangs
        // into the `bottomInset` gap the bar already leaves above the work area.
        super.init(
            contentRect: OverlayPlacement.auxiliaryFrame(
                size: size,
                anchoredTo: anchor.offsetBy(dx: 0, dy: -glow)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        // **The one overlay window with no shadow, and the glow is why.**
        // §8 deviation 1 has AppKit derive the shadow from the content's alpha. That
        // works for a hard-edged shape, but this content is a capsule wrapped in a soft
        // halo that fades out near the window's edges — AppKit thresholds that alpha and
        // takes the *glow's* outer envelope as the silhouette, then draws a shadow
        // around it. The result is a dark ring standing off the capsule by exactly the
        // glow padding: a black border with a gap. Rendering the same content over white
        // shows nothing of the kind, which is how it was pinned on the window rather
        // than the view. The bloom already separates the capsule from the wallpaper,
        // which is the whole job deviation 1 exists for.
        hasShadow = false
        animationBehavior = .none
        ignoresMouseEvents = false

        contentView = NSHostingView(
            rootView: GeneratingCapsule(label: label, onCancel: onCancel)
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// §8 deviation 4 — **the** product moment, and the only colour in the overlay.
///
/// Two copies of the same rotating border: a blurred one that falls onto the padding
/// around the capsule, and a crisp one on the outline itself. `generating.png` shows a
/// bloom rather than a hairline, and a 1.5 pt stroke alone is not what that looks like.
struct GeneratingCapsule: View {
    let label: String
    let onCancel: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tokens.Overlay.textPrimary)

            Text(label)
                .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                .foregroundStyle(Tokens.Overlay.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Tokens.Overlay.textTertiary)
                    // A 9 pt glyph is a 9 pt target. The frame is the hit area.
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
        }
        .padding(.horizontal, 14)
        .frame(
            width: Tokens.Geometry.generatingCapsuleWidth,
            height: Tokens.Geometry.generatingCapsuleHeight
        )
        .background(Capsule().fill(Tokens.Overlay.canvas))
        // **1 pt, not 1.5.** Measured perpendicular to the ring in
        // `reference/generating.png`: the core is a single pixel on a capsule the same
        // height as ours, with ~8 pt of falloff either side of it. Almost all of what
        // reads as a border there is glow.
        .overlay(border(width: 1))
        .background {
            // Drawn behind the fill, so only the half outside the capsule survives.
            // Two layers, because the reference's ring is white at the core and
            // coloured in the spill: a wide chromatic halo with a tight white bloom
            // sitting on top of it.
            ZStack {
                border(width: 3)
                    .blur(radius: 9)
                    .opacity(0.9)
                Capsule()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .blur(radius: 2.5)
                    .opacity(0.3)
            }
        }
        .padding(.top, Tokens.Geometry.generatingGlowSpread)
        .padding(.horizontal, Tokens.Geometry.generatingGlowSpread)
        .padding(.bottom, Tokens.Geometry.generatingGlowPadding)
        .onAppear {
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }

    /// A square of gradient turning behind a capsule-shaped hole.
    ///
    /// **The shape must not be what rotates**, which is what this used to do: a stroked
    /// capsule spun by `rotationEffect` and masked back to its own un-rotated outline.
    /// That only works while the two overlap, and a 176×36 capsule turned 90° is a
    /// 36×176 one — it leaves the mask almost entirely, so the border thinned to a few
    /// stray pixels and vanished twice per revolution. Nobody caught it because the
    /// capsule is on screen for a second or two at a time.
    ///
    /// The gradient is square and sized to the capsule's diagonal so it covers the
    /// outline at every angle, and only it turns. `rotationEffect` is also the reason
    /// this is a rotating *view* rather than an `AngularGradient(angle:)` rebuilt each
    /// frame — a gradient is not animatable, so the spin would jump straight to 360°.
    private func border(width: CGFloat) -> some View {
        Color.clear
            .overlay {
                GeometryReader { proxy in
                    let side = hypot(proxy.size.width, proxy.size.height)
                    Tokens.Overlay.generatingGradient
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(rotation))
                        .offset(
                            x: (proxy.size.width - side) / 2,
                            y: (proxy.size.height - side) / 2
                        )
                }
            }
            .mask(Capsule().strokeBorder(lineWidth: width))
    }
}
