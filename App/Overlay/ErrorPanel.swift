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

    private weak var anchorWindow: NSWindow?
    private var anchorFrame: NSRect
    private var zone: SnapZone
    private var measuredHeight: CGFloat = 62
    private var host: NSHostingView<ErrorToast>?

    init(anchor: NSWindow, zone: SnapZone, message: String, onDismiss: @escaping () -> Void) {
        anchorWindow = anchor
        anchorFrame = anchor.frame
        self.zone = zone
        let area = OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: anchor.frame))
        let size = NSSize(width: min(Tokens.Geometry.errorToastWidth, area.width), height: 62)
        super.init(
            contentRect: BarPlacement.stackedFrame(size: size, gap: 8, zone: zone,
                anchor: anchor.frame, workArea: area),
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

        let host = NSHostingView(rootView: ErrorToast(message: message, width: size.width,
            onDismiss: onDismiss) { [weak self] height in
                self?.applyContentHeight(height)
            })
        host.sizingOptions = []
        self.host = host
        contentView = host

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

    func reanchor(zone: SnapZone) {
        self.zone = zone
        updateFrame()
    }

    @objc private func anchorMoved() { updateFrame() }

    private func applyContentHeight(_ height: CGFloat) {
        measuredHeight = min(max(height, Tokens.Geometry.errorToastMinHeight),
                             Tokens.Geometry.errorToastMaxHeight)
        updateFrame()
    }

    private func updateFrame() {
        if let anchorWindow { anchorFrame = anchorWindow.frame }
        // Resolve the screen from the anchor, never from the proposed toast frame:
        // a toast beside a display edge can initially lie on the neighboring screen.
        let area = OverlayPlacement.workArea(on: OverlayPlacement.screen(containing: anchorFrame))
        let size = NSSize(width: min(Tokens.Geometry.errorToastWidth, area.width),
                          height: min(measuredHeight, area.height))
        if let host, host.rootView.width != size.width { host.rootView.width = size.width }
        let target = BarPlacement.stackedFrame(size: size, gap: 8, zone: zone,
                                              anchor: anchorFrame, workArea: area)
        guard target != frame else { return }
        setFrame(target, display: true)
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
    var width: CGFloat = Tokens.Geometry.errorToastWidth
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
        .frame(width: width)
        .background(SmokedGlassSurface(
            shape: RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
        ))
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
