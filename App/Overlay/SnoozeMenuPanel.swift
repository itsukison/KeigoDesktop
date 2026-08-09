import AppKit
import DesktopRewriteKit
import SwiftUI

/// The bar's right-click menu: hide it, or disable the copy-triggered reply arm
/// (§16), each for 10 minutes or 1 hour.
///
/// **A panel, not an `NSMenu`.** Every other piece of overlay chrome — the capsule,
/// the result card, the reply pill — is a custom `NSPanel` drawn from `Tokens.Overlay`
/// (§8: "the overlay is its own dark ramp"); a system `NSMenu` renders in the OS's own
/// vibrant material and system font regardless of `appearance`, and would be the one
/// piece of chrome on the bar that visibly does not belong to it. So this is built the
/// same way the rest of the bar is, anchored **above** it rather than at the click
/// point — macOS flips a real context menu upward near the bottom of the screen for
/// free, but there is no such flip to inherit once this is our own window, so the
/// anchor does the same job on purpose.
///
/// **Key, unlike every other auxiliary panel here.** `PillPanel` itself must never
/// take key (§4) — hovering it would steal the user's own field's focus mid-capture —
/// but nothing is being captured while this menu is open, and a menu that cannot catch
/// a click outside itself or an Escape key has no way to close except by picking an
/// item. `OverlayController` mirrors `panelResignedKey`'s bounce-guarded pattern to
/// dismiss this on resigning key.
final class SnoozeMenuPanel: NSPanel {

    /// The bottom edge, in screen coordinates — `anchor.maxY` plus the same gap
    /// `ReplyContextPanel` uses above the bar. Recomputed into every resize rather than
    /// read back off `frame`, for the reason `ErrorPanel.desiredBottom` documents:
    /// `NSHostingView` re-satisfies its own constraints after `applyContentHeight` sets
    /// the frame, and holds the window's *top* while doing it.
    private let desiredBottom: CGFloat

    init(
        anchor: NSRect,
        isCopyDisabled: Bool,
        copyDisabledRemainingMinutes: Int?,
        onHide: @escaping (OverlaySnooze.Duration) -> Void,
        onDisableCopy: @escaping (OverlaySnooze.Duration) -> Void,
        onCancelCopyDisable: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        // A first guess only, same contract as `ErrorPanel` — `applyContentHeight`
        // measures the real thing once SwiftUI lays it out and resizes from there.
        let size = NSSize(width: Tokens.Geometry.snoozeMenuWidth, height: 120)
        desiredBottom = anchor.maxY + Tokens.Geometry.replyContextGap
        super.init(
            contentRect: OverlayPlacement.clampToWorkArea(
                NSRect(
                    x: anchor.midX - size.width / 2,
                    y: desiredBottom,
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
        hasShadow = true // §8 deviation 1, drawn outside the frame
        animationBehavior = .none

        contentView = NSHostingView(
            rootView: SnoozeMenu(
                isCopyDisabled: isCopyDisabled,
                copyDisabledRemainingMinutes: copyDisabledRemainingMinutes,
                onHide: onHide,
                onDisableCopy: onDisableCopy,
                onCancelCopyDisable: onCancelCopyDisable,
                onDismiss: onDismiss
            ) { [weak self] height in
                self?.applyContentHeight(height)
            }
        )
    }

    /// Grows **upward** — the bottom edge stays on `desiredBottom` so the menu never
    /// drifts down into the bar it is anchored to, the same shape `ResultPanel` and
    /// `ErrorPanel` use.
    private func applyContentHeight(_ height: CGFloat) {
        var target = frame
        target.size.height = height
        target.origin.y = desiredBottom
        guard target != frame else { return }
        setFrame(OverlayPlacement.clampToWorkArea(target), display: true)
        invalidateShadow()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct SnoozeMenuHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Two groups, a hairline between them. The hide group has no toggle-off row — if this
/// menu is open at all, the bar is visible, which is the one state a hide can't be
/// active in. The copy group does need one: disabling the copy trigger never hides the
/// bar, so the bar (and this menu) stays reachable the whole time it is in force.
struct SnoozeMenu: View {
    let isCopyDisabled: Bool
    let copyDisabledRemainingMinutes: Int?
    let onHide: (OverlaySnooze.Duration) -> Void
    let onDisableCopy: (OverlaySnooze.Duration) -> Void
    let onCancelCopyDisable: () -> Void
    let onDismiss: () -> Void
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(OverlaySnooze.Duration.allCases, id: \.self) { duration in
                SnoozeMenuRow(title: "敬語ボタンを\(duration.label)非表示にする") { onHide(duration) }
            }

            hairline

            if isCopyDisabled {
                SnoozeMenuRow(
                    title: "コピー機能を有効にする（残り\(copyDisabledRemainingMinutes ?? 0)分）",
                    action: onCancelCopyDisable
                )
            } else {
                ForEach(OverlaySnooze.Duration.allCases, id: \.self) { duration in
                    SnoozeMenuRow(title: "コピー機能を\(duration.label)無効にする") { onDisableCopy(duration) }
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: Tokens.Geometry.snoozeMenuWidth)
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
                Color.clear.preference(key: SnoozeMenuHeightKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SnoozeMenuHeightKey.self) { onHeightChange($0) }
        // Both, deliberately, for the same reason `InputBar` wires both: a focused
        // control can swallow Escape often enough that `onExitCommand` alone cannot be
        // relied on. There is no text field here, but the row `Button`s are focusable.
        .onExitCommand { onDismiss() }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Tokens.Overlay.hairline)
            .frame(height: 1)
            .padding(.vertical, 6)
    }
}

private struct SnoozeMenuRow: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                .foregroundStyle(Tokens.Overlay.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: Tokens.Geometry.snoozeMenuRowHeight)
                .background(isHovering ? Tokens.Overlay.controlHover : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .cursor(.pointingHand)
    }
}
