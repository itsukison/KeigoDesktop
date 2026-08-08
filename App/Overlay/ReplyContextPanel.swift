import AppKit
import DesktopRewriteKit
import SwiftUI

/// What you are replying to, kept on screen while you type it (§16).
///
/// A second pill sitting above the bar, up from the moment a copy arms and gone when it
/// is spent. `ErrorPanel` is the precedent — the one other thing that stacks above the
/// bar while the bar is still visible and still key.
///
/// **One line, at a fixed height, and that is a bug fix rather than a style.** This was
/// a measured two-row card, and a measured height is what broke it: the same failure
/// `ErrorPanel` documents. An inflated measurement makes the window taller than the
/// space above the bar, `clampToWorkArea` then slides that window *down* to keep it on
/// screen, and because the content is bottom-aligned inside it the card draws lower
/// than its own anchor — directly over the bar. A constant height cannot inflate, so
/// the position is a pure function of the bar's frame and the whole class is gone.
///
/// The message is truncated rather than scrolled as a result. `replyTo` still carries
/// the full text; only the display is cut.
final class ReplyContextPanel: NSPanel {

    /// Which copy this card is showing. `OverlayController` compares it to decide
    /// between re-anchoring the existing card and building a new one.
    let source: ReplySource

    /// The bar's frame, as last known. The only input to `applyFrame`.
    private var anchor: NSRect

    init(anchor: NSRect, source: ReplySource, onDismiss: @escaping () -> Void) {
        self.source = source
        self.anchor = anchor
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
            rootView: ReplyContextPill(source: source, onDismiss: onDismiss)
        )
    }

    /// Sits `replyContextGap` above the bar, centred on it, at the composer's width so
    /// the two line up as one column once the input box opens.
    static func frame(anchoredTo anchor: NSRect) -> NSRect {
        OverlayPlacement.clampToWorkArea(
            NSRect(
                x: anchor.midX - Tokens.Geometry.inputBarWidth / 2,
                y: anchor.maxY + Tokens.Geometry.replyContextGap,
                width: Tokens.Geometry.inputBarWidth,
                height: Tokens.Geometry.replyContextHeight
            )
        )
    }

    /// Follows the bar. The input bar wraps to `inputBarMaxLines` as the user types, so
    /// the thing this pill sits on top of gets taller *during* composition — pinned at
    /// creation it would be grown into by the second line.
    func reanchor(to anchor: NSRect) {
        self.anchor = anchor
        let target = Self.frame(anchoredTo: anchor)
        guard target != frame else { return }
        setFrame(target, display: true)
        invalidateShadow()
    }

    /// Never key. `OverlayController.panelResignedKey` cancels the composer when
    /// `PillPanel` loses key, so a pill that could take focus would close the input bar
    /// the moment anyone clicked the message they were reading.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// `[↩]  the copied message, in italic  [✕]` — one row, the same capsule as the bar.
struct ReplyContextPill: View {
    let source: ReplySource
    let onDismiss: () -> Void

    @State private var isHoveringDismiss = false

    var body: some View {
        HStack(spacing: 8) {
            // Carries what a 「返信先」 label used to say. On one line the label and the
            // icon are the same word twice, and the message needs the width more.
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Tokens.Overlay.textTertiary)

            // Italic because it is a quotation — someone else's words, sitting above
            // the field where yours go. It is also the one thing separating it from the
            // bar's own labels at a glance.
            Text(source.contextText)
                .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                .italic()
                .foregroundStyle(Tokens.Overlay.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

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
        .padding(.horizontal, 12)
        // Fills the window exactly. The window's height is the token, not a
        // measurement, so nothing here may ask to be taller than it.
        .frame(
            width: Tokens.Geometry.inputBarWidth,
            height: Tokens.Geometry.replyContextHeight
        )
        .background(
            // `canvas`, like the bar — the two are siblings floating over the same
            // wallpaper, separated by `replyContextGap`, not a card and its contents.
            Capsule().fill(Tokens.Overlay.canvas)
        )
    }
}
