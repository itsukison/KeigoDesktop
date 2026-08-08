import AppKit
import DesktopRewriteKit
import SwiftUI

/// Reports the content's intrinsic size up to the controller.
///
/// The window frame is what animates (§4), so something has to decide how big it
/// should be. Computing that by hand does not work: `NSHostingView` installs its own
/// constraints from SwiftUI's intrinsic size and simply overrides whatever frame was
/// set, so a hand-measured width is both dead code and a visible size jump. Let
/// SwiftUI measure, and drive the window from that.
///
/// Height is measured too. It is still a design decision — §4's 28/34 pt are a
/// *floor* — but the input bar wraps to as many as `inputBarMaxLines`, and a window
/// pinned to 34 pt would clip the second line.
private struct ContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

/// The pill, the hover row and the input bar — one window at three sizes (§4).
struct PillRootView: View {
    @ObservedObject var controller: OverlayController

    var body: some View {
        ZStack {
            // No SwiftUI `.shadow` here. The window is sized exactly to this shape, so
            // a shadow drawn inside it is clipped to the window bounds and all that
            // survives is a grey smear in the four corners — the pill's rounded
            // corners are the only place the shadow is not hidden under the fill.
            // `PillPanel.hasShadow` draws the real one, outside the frame (§8).
            RoundedRectangle(cornerRadius: Tokens.Overlay.pillRadius, style: .continuous)
                .fill(Tokens.Overlay.canvas)

            content
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ContentSizeKey.self, value: proxy.size)
                    }
                )
        }
        .frame(minHeight: controller.state.contentHeight)
        .fixedSize(horizontal: true, vertical: true)
        .onPreferenceChange(ContentSizeKey.self) { size in
            controller.contentSizeChanged(size)
        }
        // The bar itself is a drag handle (`isMovableByWindowBackground`), so the
        // background says so. Buttons drawn on top of it declare `.pointingHand` and
        // win, because a cursor area nested inside the content sits in front of one
        // installed behind it.
        //
        // Not in the input bar, though. That state is a text field, the field brings
        // its own I-beam, and a hand stretched across the whole bar would be claiming
        // the one place the pointer means something else.
        .background {
            if !controller.state.wantsKeyWindow {
                CursorArea(cursor: .openHand)
            }
        }
        .background(HoverTracker(
            onEnter: { controller.mouseEntered() },
            onExit: { controller.mouseExited() },
            onDragEnded: { controller.persistPosition() }
        ))
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .pill, .generating, .result:
            // The padding is load-bearing, not decoration. The window follows this
            // measurement, so a bare 16 pt mark would make the collapsed pill 16 pt
            // wide — a naked icon, not the pill `normal.png` shows. 16 + 2×14 lands
            // on `Tokens.Geometry.pillCollapsedWidth`, which also means the window
            // never resizes on first layout and so never drifts off centre.
            BrandMark()
                .padding(.horizontal, (Tokens.Geometry.pillCollapsedWidth - 16) / 2)
        case .hoverRow:
            HoverRow(controller: controller)
        case .inputBar, .replyInput:
            InputBar(controller: controller)
        case .replyArmed:
            ReplyBar()
        }
    }
}

/// The mark shown on the collapsed pill and at the left of the expanded row.
///
/// The colour cut, not the outline one — see `BrandGlyph`. It must stay 16×16: the
/// collapsed pill's width is `16 + 2 × padding` and the window measures the content.
struct BrandMark: View {
    var body: some View {
        BrandGlyph(size: 16)
    }
}

/// §4 hover-row layout, option C: mark, hairline, the user's own buttons as text
/// labels, hairline, ✎.
///
/// Labels rather than icons because a user's buttons have arbitrary titles — there is
/// no icon vocabulary that can carry 「敬語」 next to a button they wrote themselves.
struct HoverRow: View {
    @ObservedObject var controller: OverlayController

    var body: some View {
        HStack(spacing: 8) {
            BrandMark()
            divider

            if controller.displayedPrompts.isEmpty {
                // Two different empty states. Telling someone to go and make buttons
                // they already have, because the fetch failed, is worse than silence.
                Text(
                    controller.promptsFailed
                        ? "ボタンを読み込めませんでした"
                        : "スマホでボタンを作成してください"
                )
                .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                .foregroundStyle(Tokens.Overlay.textTertiary)
            } else {
                ForEach(controller.displayedPrompts) { prompt in
                    RowPill(title: prompt.title) { controller.press(prompt) }
                }
            }

            divider
            RowPill(systemImage: "pencil") { controller.pressCustomInput() }
        }
        .padding(.horizontal, 12)
    }

    private var divider: some View {
        Rectangle()
            .fill(Tokens.Overlay.hairline)
            .frame(width: 1, height: 16)
    }
}

/// Transparent until hover, then the hairline value — `surface` sits too close to
/// `canvas` for a hover state to read.
struct RowPill: View {
    var title: String?
    var systemImage: String?
    let action: () -> Void

    @State private var isHovering = false

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = nil
        self.action = action
    }

    init(systemImage: String, action: @escaping () -> Void) {
        self.title = nil
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                        .font(Tokens.Font.body(Tokens.Overlay.labelMedium, weight: .medium))
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundStyle(Tokens.Overlay.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                Capsule().fill(isHovering ? Tokens.Overlay.controlHover : .clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .cursor(.pointingHand)
    }
}

/// The armed reply bar (§16) — what a copy turns the collapsed pill into.
///
/// **It carries no preview, deliberately.** It used to, and that was the whole design
/// error: `ReplyContextPanel` is now up from the moment a copy arms, so a truncated
/// copy of the same message in the bar underneath is duplication that has to be kept in
/// sync and re-truncated at a second width. The bar's only job here is to say that
/// hovering it opens a reply rather than the button row — which is one badge.
///
/// Dismissal lives on the card, next to the thing being dismissed.
struct ReplyBar: View {
    var body: some View {
        HStack(spacing: 8) {
            BrandMark()

            Text("返信")
                .font(Tokens.Font.body(Tokens.Overlay.labelSmall, weight: .medium))
                .foregroundStyle(Tokens.Overlay.textPrimary)
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(Tokens.Overlay.hairline))
        }
        .padding(.horizontal, 12)
    }
}

/// The free-text path, in both of its modes.
///
/// The target was already captured — when ✎ was pressed for a rewrite, and on hover
/// for a reply (§16) — so this field is safe to make key either way.
struct InputBar: View {
    @ObservedObject var controller: OverlayController
    @State private var text = ""
    @FocusState private var focused: Bool

    private var isReply: Bool {
        if case .replyInput = controller.state { return true }
        return false
    }

    /// Empty submits are allowed in reply mode and blocked in rewrite mode. There is
    /// no rewrite without an instruction, but "just write me a reply" is a request —
    /// `OverlayController.defaultReplyInstruction` is what actually goes over the wire.
    private var canSubmit: Bool {
        isReply || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        // Centred, not top-aligned. Top alignment is only right while the field is
        // wrapped, and it is on one line almost always — which left the text sitting
        // high in the bar in the common case.
        HStack(spacing: 8) {
            BrandMark()

            if isReply {
                // The bar arrived here from a state that showed the copied message, and
                // the message itself is too long to keep on screen while typing. This
                // is what is left of it: a reminder of which mode Return is about to
                // submit into.
                Text("返信")
                    .font(Tokens.Font.body(Tokens.Overlay.labelSmall, weight: .medium))
                    .foregroundStyle(Tokens.Overlay.textPrimary)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(Capsule().fill(Tokens.Overlay.hairline))
            }

            // `axis: .vertical` + a line-limit range is what makes a long prompt wrap
            // instead of running off the side. Return still submits; the range only
            // governs wrapping.
            TextField(
                isReply ? "どう返信しますか？（空欄でおまかせ）" : "どう書き換えますか？",
                text: $text,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
            .foregroundStyle(Tokens.Overlay.textPrimary)
            .lineLimit(1...Tokens.Geometry.inputBarMaxLines)
            .focused($focused)
            .onSubmit { controller.submitInput(text) }

            Button {
                controller.submitInput(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(
                        canSubmit ? Tokens.Overlay.textPrimary : Tokens.Overlay.textTertiary
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .cursor(canSubmit ? .pointingHand : .arrow)
        }
        .padding(.horizontal, 12)
        // Vertical padding so a wrapped second line has somewhere to go, and a fixed
        // width so the bar does not resize under the cursor while typing.
        .padding(.vertical, 8)
        .frame(width: Tokens.Geometry.inputBarWidth)
        .onAppear { focused = true }
        // Both, deliberately. A focused `TextField` swallows Escape often enough that
        // `onExitCommand` alone cannot be relied on, and `cancelInput` is idempotent,
        // so a double delivery costs nothing.
        .onExitCommand { controller.cancelInput() }
        .onKeyPress(.escape) {
            controller.cancelInput()
            return .handled
        }
    }
}

/// §4: an `NSTrackingArea` with a hit area a few points larger than the visible pill,
/// kept strictly inside `visibleFrame` so it never fights Dock magnification.
private struct HoverTracker: NSViewRepresentable {
    let onEnter: () -> Void
    let onExit: () -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onEnter = onEnter
        view.onExit = onExit
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onEnter = onEnter
        nsView.onExit = onExit
        nsView.onDragEnded = onDragEnded
    }

    final class TrackingView: NSView {
        var onEnter: (() -> Void)?
        var onExit: (() -> Void)?
        var onDragEnded: (() -> Void)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds.insetBy(dx: -4, dy: -2),
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { onEnter?() }
        override func mouseExited(with event: NSEvent) { onExit?() }

        /// `isMovableByWindowBackground` does the dragging; this just records where it
        /// ended up so the offset can be persisted (§4).
        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            onDragEnded?()
        }
    }
}
