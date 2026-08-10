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
private struct ContentMeasurement: Equatable {
    let size: CGSize
    let layout: OverlayContentLayout
}

private struct ContentSizeKey: PreferenceKey {
    static let defaultValue: ContentMeasurement? = nil
    static func reduce(value: inout ContentMeasurement?, nextValue: () -> ContentMeasurement?) {
        if let next = nextValue() { value = next }
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
                        Color.clear.preference(
                            key: ContentSizeKey.self,
                            value: ContentMeasurement(
                                size: proxy.size,
                                layout: controller.state.contentLayout
                            )
                        )
                    }
                )
        }
        .frame(minHeight: controller.state.contentHeight)
        .fixedSize(horizontal: true, vertical: true)
        .onPreferenceChange(ContentSizeKey.self) { measurement in
            guard let measurement else { return }
            controller.contentSizeChanged(measurement.size, for: measurement.layout)
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
        case .pill:
            // The right-click catcher is attached here and on `HoverRow` only — never
            // on `.inputBar` / `.replyInput`, where the field underneath already has
            // AppKit's own right-click edit menu (copy/paste/etc.) and an ancestor
            // claiming the right-click first would break it.
            pillMark.background(RightClickCatcher { controller.toggleSnoozeMenu() })
        case .generating, .result:
            pillMark
        case .hoverRow:
            HoverRow(controller: controller)
                .background(RightClickCatcher { controller.toggleSnoozeMenu() })
        case .inputBar, .replyInput:
            InputBar(controller: controller)
        case .replyArmed:
            ReplyBar()
        }
    }

    // The padding is load-bearing, not decoration. The window follows this
    // measurement, so a bare 16 pt mark would make the collapsed pill 16 pt wide — a
    // naked icon, not the pill `normal.png` shows. 16 + 2×14 lands on
    // `Tokens.Geometry.pillCollapsedWidth`, which also means the window never resizes
    // on first layout and so never drifts off centre.
    private var pillMark: some View {
        BrandMark()
            .padding(.horizontal, (Tokens.Geometry.pillCollapsedWidth - 16) / 2)
    }
}

/// Catches a right click and hands it to `OverlayController.toggleSnoozeMenu()`.
///
/// **Not `.contextMenu`.** A SwiftUI context menu opens a system `NSMenu`, which
/// renders in the OS's own material and font no matter what `Tokens.Overlay` says —
/// `SnoozeMenuPanel` is a custom window styled from the same tokens as the rest of the
/// bar instead (see its own doc comment for why that is worth the extra window).
private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> TriggerView {
        let view = TriggerView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: TriggerView, context: Context) {
        nsView.onRightClick = onRightClick
    }

    final class TriggerView: NSView {
        var onRightClick: (() -> Void)?
        override func rightMouseDown(with event: NSEvent) { onRightClick?() }
    }
}

/// The mark shown on the collapsed pill and at the left of the expanded row.
///
/// The colour cut, not the outline one — see `BrandGlyph`. It must stay 16×16: the
/// collapsed pill's width is `16 + 2 × padding` and the window measures the content.
struct BrandMark: View {
    var animation: MascotAnimation = .idle

    var body: some View {
        BrandGlyph(size: 16, animation: animation)
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
            BrandMark(animation: .engaged)
            divider

            if controller.signedOut {
                // **The one empty row that is not an apology.** Signed out, every
                // control on this bar is inert — the buttons live on the account and
                // ✎ can only end in a failed rewrite — so the row is replaced by the
                // single action that changes that, rather than reporting that the
                // buttons could not be loaded and leaving the user to guess why.
                Text(tr("サインインするとボタンが使えます", "Sign in to use your buttons", "登录后即可使用按钮"))
                    .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                    .foregroundStyle(Tokens.Overlay.textSecondary)
                RowPill(title: tr("サインイン", "Sign in", "登录"), emphasised: true) { controller.pressSignIn() }
            } else {
                if controller.displayedPrompts.isEmpty {
                    // Two different empty states. Telling someone to go and make
                    // buttons they already have, because the fetch failed, is worse
                    // than silence.
                    Text(
                        controller.promptsFailed
                            ? tr("ボタンを読み込めませんでした", "Couldn't load your buttons", "无法加载按钮")
                            : tr(
                                "スマホでボタンを作成してください",
                                "Create a button to get started",
                                "请先创建一个按钮"
                            )
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
///
/// `emphasised` inverts it to a filled pill for the one row that holds a single
/// action and nothing else (signed out). It fills with `textPrimary` rather than
/// introducing a colour: §8 keeps the generating capsule as the overlay's only
/// colour, and the dark ramp's own white is the loudest thing available here.
struct RowPill: View {
    var title: String?
    var systemImage: String?
    var emphasised = false
    let action: () -> Void

    @State private var isHovering = false

    init(title: String, emphasised: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = nil
        self.emphasised = emphasised
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
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .cursor(.pointingHand)
    }

    private var foreground: Color {
        emphasised ? Tokens.Overlay.canvas : Tokens.Overlay.textPrimary
    }

    private var fill: Color {
        guard emphasised else { return isHovering ? Tokens.Overlay.controlHover : .clear }
        return Tokens.Overlay.textPrimary.opacity(isHovering ? 0.88 : 1)
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
            BrandMark(animation: .engaged)

            Text(tr("返信", "Reply", "回复"))
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

    /// Rendered separately from the field. AppKit's native placeholder ignores the
    /// overlay foreground in a non-activating panel and follows the system appearance,
    /// which can put black text on this always-dark bar.
    private var placeholderText: String {
        isReply
            ? tr(
                "返信の指示（空欄でおまかせ）",
                "Reply instructions (optional)",
                "回复要求（可留空）"
            )
            : tr("どう書き換えますか？", "How should this be rewritten?", "想怎么改写？")
    }

    var body: some View {
        // Centred, not top-aligned. Top alignment is only right while the field is
        // wrapped, and it is on one line almost always — which left the text sitting
        // high in the bar in the common case.
        HStack(spacing: 8) {
            BrandMark(animation: .engaged)

            ZStack(alignment: .leading) {
                // One line regardless of mode. Typed guidance may grow to three lines,
                // but a hint must not make the bar taller before the user writes.
                if text.isEmpty {
                    Text(placeholderText)
                        .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
                        .foregroundStyle(Tokens.Overlay.textSecondary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                // `axis: .vertical` + a line-limit range is what lets the user's own
                // long guidance wrap. Return still submits; the range governs wrapping.
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
                    .foregroundStyle(Tokens.Overlay.textPrimary)
                    .lineLimit(1...Tokens.Geometry.inputBarMaxLines)
                    .focused($focused)
                    .accessibilityLabel(placeholderText)
                    .onSubmit { controller.submitInput(text) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

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
