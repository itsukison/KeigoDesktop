import AppKit
import DesktopRewriteKit
import SwiftUI

/// Errors used to be an `.overlay` on `PillRootView` offset 34 pt above the pill —
/// i.e. outside a window sized exactly to the pill, so it was clipped away and never
/// drew. Pressing a button in an app with no editable field did nothing at all, which
/// is the most likely thing to happen on a first run.
///
/// Its own window, because the bar's window is sized to the bar and a message does not
/// fit in 28 pt. Never key: the failure that produced it usually left the user's own
/// field focused, and stealing that to show an apology would make it worse.
final class ErrorPanel: NSPanel {

    /// The bottom edge the toast is supposed to keep, in screen coordinates.
    ///
    /// Recomputed into every resize rather than read back off `frame`, because the frame
    /// is not ours alone: `NSHostingView` re-satisfies its own constraints afterwards and
    /// holds the window's **top**, so growing by 6 pt moved the bottom 6 pt *down* and
    /// ate the gap above the bar. Deriving the origin from the anchor makes the position
    /// the same no matter who resized last.
    private let desiredBottom: CGFloat

    init(anchor: NSRect, message: String, onDismiss: @escaping () -> Void) {
        // A first guess only — `applyContentHeight` measures the wrapped message and
        // resizes. Close to the one-line case so the toast does not visibly settle.
        let size = NSSize(width: Tokens.Geometry.errorToastWidth, height: 62)
        desiredBottom = anchor.maxY + 8
        super.init(
            contentRect: OverlayPlacement.clampToWorkArea(
                NSRect(
                    x: anchor.midX - size.width / 2,
                    // Above whatever is currently holding the bottom edge — the bar,
                    // the generating capsule, or a result card up to 440 pt tall.
                    y: anchor.maxY + 8,
                    width: size.width,
                    height: size.height
                )
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
        hasShadow = true
        animationBehavior = .none

        contentView = NSHostingView(
            rootView: ErrorToast(message: message, onDismiss: onDismiss) { [weak self] height in
                self?.applyContentHeight(height)
            }
        )
    }

    /// Same measure-then-resize contract as `ResultPanel`: the message wraps, so the
    /// height is not knowable up front. Grows **upward** — the bottom edge is anchored
    /// to whatever the toast is sitting on top of.
    ///
    /// **Clamped, and that is not defensive dressing.** `ResultPanel` has always bounded
    /// this and the toast never did, which is the whole reason one of them worked: with
    /// an unbounded measurement (see `ErrorToast`) the window went to 721 pt, and a
    /// 721 pt window anchored near the bottom of the screen puts its bottom-aligned card
    /// 653 pt *below* the display. The toast was on screen, opaque and unoccluded the
    /// entire time — just nowhere anybody could see it.
    private func applyContentHeight(_ height: CGFloat) {
        let clamped = min(max(height, Tokens.Geometry.errorToastMinHeight),
                          Tokens.Geometry.errorToastMaxHeight)
        var target = frame
        target.size.height = clamped
        target.origin.y = desiredBottom
        guard target != frame else { return }
        setFrame(OverlayPlacement.clampToWorkArea(target), display: true)
        invalidateShadow()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct ToastHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ErrorToast: View {
    let message: String
    let onDismiss: () -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Tokens.Overlay.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
                    .foregroundStyle(Tokens.Overlay.textPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Says the toast is dismissible, and — more usefully — that it is not
                // going to stand there forever if it is ignored.
                Text(tr("クリックで閉じる", "Click to dismiss", "点击关闭"))
                    .font(Tokens.Font.body(Tokens.Overlay.labelSmall))
                    .foregroundStyle(Tokens.Overlay.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        // **Fixed width, no `maxHeight: .infinity`, and that pairing is the bug.**
        // The toast used to end with `.frame(maxHeight: .infinity, alignment: .bottom)`,
        // copied from `ResultView` where a clamp downstream hides what it does. Inside
        // an `NSHostingView` that frame is unbounded in the only direction that matters:
        // the card's own `GeometryReader` reported the stretched height, `NSHostingView`
        // installed constraints for it, and the window went to 721 pt. Anchored near the
        // bottom of the screen, that put the bottom-aligned card 653 pt below the
        // display — the toast was ordered front, opaque and unoccluded the whole time,
        // and simply off screen. Sizing the card to itself is the fix; the window then
        // follows the measurement instead of fighting it.
        .frame(width: Tokens.Geometry.errorToastWidth)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
                .fill(Tokens.Overlay.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
                .strokeBorder(Tokens.Overlay.hairline, lineWidth: 1)
        )
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ToastHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(ToastHeightKey.self) { onHeightChange($0) }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .cursor(.pointingHand)
    }
}
