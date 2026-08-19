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

    /// The window the toast sits on top of — the bar, the generating capsule, or the
    /// result card.
    ///
    /// **A reference, not the rectangle it had at the time, and that was the bug.** The
    /// result panel is created at `resultPanelMaxHeight` (440) and only then measures its
    /// content and shrinks, bottom-fixed, to as little as 160. An insert failure raises
    /// this toast in the same turn as it re-creates that panel, so a snapshot of the
    /// anchor was always the 440 pt guess: the toast settled up to 280 pt above a card
    /// that had since shrunk out from under it, which is the floating message with a hole
    /// beneath it. Weak, because the anchor can be ordered out while the toast is still
    /// up — the last known bottom is then the right thing to keep.
    private weak var anchorWindow: NSWindow?
    private var desiredBottom: CGFloat

    init(anchor: NSWindow, message: String, onDismiss: @escaping () -> Void) {
        // A first guess only — `applyContentHeight` measures the wrapped message and
        // resizes. Close to the one-line case so the toast does not visibly settle.
        let size = NSSize(width: Tokens.Geometry.errorToastWidth, height: 62)
        let frame = anchor.frame
        anchorWindow = anchor
        desiredBottom = frame.maxY + 8
        super.init(
            contentRect: OverlayPlacement.clampToWorkArea(
                NSRect(
                    x: frame.midX - size.width / 2,
                    // Above whatever is currently holding the bottom edge — the bar,
                    // the generating capsule, or a result card up to 440 pt tall.
                    y: frame.maxY + 8,
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

        // The anchor settles *after* this returns — `NSHostingView` measures the card and
        // resizes the window on a later pass — and it can settle more than once. Both
        // notifications, because a result panel that shrinks keeps its bottom edge and so
        // only reports a resize, while the bar being dragged only reports a move.
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(anchorMoved),
                name: name,
                object: anchor
            )
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func anchorMoved() {
        guard let anchorWindow else { return }
        desiredBottom = anchorWindow.frame.maxY + 8
        var target = frame
        target.origin.y = desiredBottom
        target.origin.x = anchorWindow.frame.midX - frame.width / 2
        guard target != frame else { return }
        setFrame(OverlayPlacement.clampToWorkArea(target), display: true)
        invalidateShadow()
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
        // Re-derived rather than carried: between construction and this call the anchor
        // has usually finished measuring itself and moved.
        if let anchorWindow { desiredBottom = anchorWindow.frame.maxY + 8 }
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
