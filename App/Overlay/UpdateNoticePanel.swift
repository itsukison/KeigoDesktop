import AppKit
import DesktopRewriteKit
import SwiftUI

/// 「新しいバージョン 0.1.3」 above the bar, with one action.
///
/// **This is the surface the gentle reminder was missing.** Sparkle's own scheduled
/// alert is declined (`AppDelegate.standardUserDriverShouldHandleShowingScheduledUpdate`)
/// because an accessory process has no Dock presence to put it in front of anything, so
/// the app took responsibility for announcing the update itself — and then announced it
/// only inside the main window, on a page an `LSUIElement` app gives nobody a reason to
/// open. Declining Sparkle's UI and replacing it with something invisible is strictly
/// worse than not declining it, which is what shipped.
///
/// The bar is the one thing this app is always showing, so the announcement goes here.
/// `ReplyContextPanel` is the precedent in every respect: a sibling window stacked above
/// the bar, constant height (a measured height inflates, and `clampToWorkArea` answers an
/// inflated window near the screen's bottom edge by sliding it *down* over the bar —
/// `ErrorPanel` documents that failure at length), and never key, because the user is
/// working in someone else's text field and an update notice is not a reason to take it.
final class UpdateNoticePanel: NSPanel {

    /// Which release this is announcing. `OverlayController` compares it so a re-find of
    /// the same version re-anchors the existing panel instead of rebuilding it.
    let version: String

    init(
        anchor: NSRect,
        version: String,
        onUpdate: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.version = version
        super.init(
            contentRect: Self.frame(anchoredTo: anchor),
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
            rootView: UpdateNoticeCard(
                version: version,
                onUpdate: onUpdate,
                onDismiss: onDismiss
            )
        )
    }

    static func frame(anchoredTo anchor: NSRect) -> NSRect {
        OverlayPlacement.clampToWorkArea(
            NSRect(
                x: anchor.midX - Tokens.Geometry.updateNoticeWidth / 2,
                y: anchor.maxY + Tokens.Geometry.replyContextGap,
                width: Tokens.Geometry.updateNoticeWidth,
                height: Tokens.Geometry.updateNoticeHeight
            )
        )
    }

    /// Follows the bar — which moves when the user drags it, when the Dock appears or
    /// hides under a full-screen space, and when the row expands under the pointer.
    func reanchor(to anchor: NSRect) {
        let target = Self.frame(anchoredTo: anchor)
        guard target != frame else { return }
        setFrame(target, display: true)
        invalidateShadow()
    }

    /// Never key, for the same reason the bar never is (§4): the user's own field is
    /// still focused and still the target of the next rewrite. Taking focus to show a
    /// version number would break the app to advertise a fix for it.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// `[mark] 新しいバージョン v0.1.3  [アップデート] [✕]` — one row, the bar's own palette.
struct UpdateNoticeCard: View {
    let version: String
    let onUpdate: () -> Void
    let onDismiss: () -> Void

    @State private var isHoveringDismiss = false

    var body: some View {
        HStack(spacing: 8) {
            // The product mark rather than a download glyph: this is the app speaking
            // about itself, and the same mark is on the bar 8 pt below.
            BrandGlyph(size: 14)

            Text(tr(
                "新しいバージョン v\(version)",
                "Version \(version) is available",
                "新版本 v\(version)"
            ))
                .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                .foregroundStyle(Tokens.Overlay.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            RowPill(
                title: tr("アップデート", "Update", "更新"),
                emphasised: true,
                action: onUpdate
            )

            // Dismissing hides *this* panel for *this* version and nothing else — the
            // status-menu row and the ホーム card stay. Waving away a reminder is not
            // refusing the update, and Sparkle still owns the real "skip this version".
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(
                        isHoveringDismiss
                            ? Tokens.Overlay.textPrimary
                            : Tokens.Overlay.textTertiary
                    )
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringDismiss = $0 }
            .cursor(.pointingHand)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        // Fills the window exactly. The window's height is the token, not a
        // measurement, so nothing in here may ask to be taller than it.
        .frame(
            width: Tokens.Geometry.updateNoticeWidth,
            height: Tokens.Geometry.updateNoticeHeight
        )
        .background(Capsule().fill(Tokens.Overlay.canvas))
    }
}
