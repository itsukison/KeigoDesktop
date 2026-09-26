import AppKit
import DesktopRewriteKit
import SwiftUI
import TextIO

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
        Group {
            if let presentation = controller.introPresentation {
                IntroPillView(presentation: presentation)
            } else {
                restingBody
            }
        }
    }

    private var restingBody: some View {
        ZStack {
            // No SwiftUI `.shadow` here. The window is sized exactly to this shape, so
            // a shadow drawn inside it is clipped to the window bounds and all that
            // survives is a grey smear in the four corners — the pill's rounded
            // corners are the only place the shadow is not hidden under the fill.
            // `PillPanel.hasShadow` draws the real one, outside the frame (§8).
            SmokedGlassSurface(shape: barShape, joinsNotch: controller.parkedZone == .topCenter)

            content
                .frame(minWidth: controller.barMinimumSize.width, minHeight: controller.barMinimumSize.height)
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
            onDragEnded: { controller.endBarDrag() }
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
        case .explicitReply, .inputBar:
            InputBar(controller: controller)
        case .replyInput(let source, _):
            VStack(spacing: 0) {
                CopiedReplyHeader(source: source, onDismiss: controller.dismissReply)
                Rectangle().fill(Tokens.Overlay.hairline).frame(height: 1).padding(.horizontal, 12)
                InputBar(controller: controller)
            }
            .frame(width: controller.usesSidebarLayout ? Tokens.Geometry.sideInputWidth : Tokens.Geometry.inputBarWidth)

        }
    }

    private var barShape: UnevenRoundedRectangle {
        let zone = controller.isDraggingBar ? SnapZone.bottomCenter : controller.parkedZone
        let radius = zone == .topCenter ? Tokens.Geometry.topCornerRadius
            : controller.usesSidebarLayout ? Tokens.Geometry.sideCornerRadius
            : controller.state.replySource != nil ? Tokens.Overlay.panelRadius : Tokens.Overlay.pillRadius
        return UnevenRoundedRectangle(
            topLeadingRadius: zone == .left || zone == .topCenter ? 0 : radius,
            bottomLeadingRadius: zone == .left ? 0 : radius,
            bottomTrailingRadius: zone == .right ? 0 : radius,
            topTrailingRadius: zone == .right || zone == .topCenter ? 0 : radius,
            style: .continuous
        )
    }

    // The padding is load-bearing, not decoration. The window follows this
    // measurement, so a bare 16 pt mark would make the collapsed pill 16 pt wide — a
    // naked icon, not the pill `normal.png` shows. 16 + 2×14 lands on
    // `Tokens.Geometry.pillCollapsedWidth`, which also means the window never resizes
    // on first layout and so never drifts off centre.
    private var pillMark: some View {
        BrandGlyph(size: 16, isAnimating: !controller.onboardingPassive)
            .overlay(alignment: .topTrailing) {
                if controller.availableReplySource != nil {
                    Circle()
                        .fill(Tokens.Overlay.textSecondary)
                        .frame(width: 4, height: 4)
                        .offset(x: 3, y: -2)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(controller.availableReplySource == nil
                ? tr("文章作成バー", "Writing bar", "写作工具条")
                : tr("文章作成バー、コピーした文章に返信できます", "Writing bar, reply to copied text available", "写作工具条，可回复已复制的文字"))
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: controller.introDragCue) { view, offset in
                view.offset(x: offset)
            } keyframes: { _ in
                CubicKeyframe(-2, duration: 0.12)
                CubicKeyframe(2, duration: 0.18)
                CubicKeyframe(0, duration: 0.15)
            }
            .frame(width: controller.barMinimumSize.width, height: controller.barMinimumSize.height)
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

/// The compact row: mark, Polish, and one-off guidance.
struct HoverRow: View {
    @ObservedObject var controller: OverlayController

    var body: some View {
        let sidebar = controller.usesSidebarLayout
        let layout = sidebar ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            BrandMark(animation: .engaged)
            divider

            if controller.signedOut {
                // **The one empty row that is not an apology.** Signed out, every
                // control on this bar is inert — the buttons live on the account and
                // ✎ can only end in a failed rewrite — so the row is replaced by the
                // single action that changes that, rather than reporting that the
                // buttons could not be loaded and leaving the user to guess why.
                Text(tr("サインインするとボタンが使えます", "Sign in to polish your writing", "登录后即可使用按钮"))
                    .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                    .foregroundStyle(Tokens.Overlay.textSecondary)
                    .multilineTextAlignment(sidebar ? .center : .leading)
                    .fixedSize(horizontal: !sidebar, vertical: true)
                RowPill(title: tr("サインイン", "Sign in", "登录"), emphasised: true, isSidebar: sidebar) { controller.pressSignIn() }
            } else {
                ScrollView(sidebar ? .vertical : .horizontal) {
                    let buttonsLayout = sidebar ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                    buttonsLayout {
                        if controller.displayedPrompts.isEmpty {
                            Text(controller.promptsFailed
                                ? tr("読み込み失敗", "Couldn't load buttons", "无法加载按钮")
                                : tr("ボタンを追加", "Add buttons in settings", "在设置中添加按钮"))
                                .font(Tokens.Font.body(12)).foregroundStyle(Tokens.Overlay.textSecondary)
                            if controller.promptsFailed {
                                Button(tr("再試行", "Retry", "重试")) { Task { await controller.refreshAccount() } }
                                    .buttonStyle(.plain)
                            }
                        }
                        ForEach(controller.displayedPrompts) { prompt in
                            RowPill(title: prompt.title, emphasised: controller.lesson?.expectedAction == .polish, isSidebar: sidebar) { controller.press(prompt) }
                                .disabled(!controller.allowsLessonAction(.polish))
                                .opacity(controller.lesson != nil && controller.lesson?.expectedAction != .polish ? 0.35 : 1)
                                .background(LessonAnchorReader(anchor: .polish, controller: controller))
                                .help(prompt.title)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .frame(width: controller.buttonViewportSize.width, height: controller.buttonViewportSize.height)
                divider
                if controller.availableReplySource != nil {
                    CopiedReplyAction(controller: controller)
                } else if ReplyContextFeature.isEnabled {
                    RowPill(title: tr("返信", "Reply", "回复"), emphasised: controller.lesson?.expectedAction == .reply, isSidebar: sidebar) { controller.pressReply() }
                        .disabled(!controller.allowsLessonAction(.reply))
                        .opacity(controller.lesson != nil && controller.lesson?.expectedAction != .reply ? 0.35 : 1)
                        .background(LessonAnchorReader(anchor: .reply, controller: controller))
                }
                RowPill(systemImage: "pencil", emphasised: controller.lesson?.expectedAction == .custom, isSidebar: sidebar) { controller.pressCustomInput() }
                    .disabled(!controller.allowsLessonAction(.custom))
                    .opacity(controller.lesson != nil && controller.lesson?.expectedAction != .custom ? 0.35 : 1)
                    .background(LessonAnchorReader(anchor: .custom, controller: controller))
                    .accessibilityLabel(tr("指示を書く", "Write instructions", "填写要求"))
            }
        }
        .padding(.horizontal, sidebar ? Tokens.Geometry.sideActionsPadding : 12)
        .padding(.vertical, sidebar ? 12 : 0)
        .frame(width: sidebar ? (controller.signedOut ? 176 : 144) : nil)
    }

    private var divider: some View {
        Rectangle()
            .fill(Tokens.Overlay.hairline)
            .frame(width: controller.usesSidebarLayout ? 40 : 1,
                   height: controller.usesSidebarLayout ? 1 : 16)
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
    var isSidebar = false
    let action: () -> Void

    @State private var isHovering = false

    init(title: String, emphasised: Bool = false, isSidebar: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = nil
        self.emphasised = emphasised
        self.isSidebar = isSidebar
        self.action = action
    }

    init(systemImage: String, emphasised: Bool = false, isSidebar: Bool = false, action: @escaping () -> Void) {
        self.title = nil
        self.systemImage = systemImage
        self.emphasised = emphasised
        self.isSidebar = isSidebar
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
            .frame(width: isSidebar ? Tokens.Geometry.sideActionsWidth - 2 * Tokens.Geometry.sideActionsPadding : nil, height: isSidebar ? 32 : 24)
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

private struct CopiedReplyAction: View {
    @ObservedObject var controller: OverlayController
    @State private var hovering = false

    var body: some View {
        let emphasised = controller.lesson?.expectedAction == .reply
        HStack(spacing: 0) {
            Button { controller.pressCopiedReply() } label: {
                Text(tr("返信", "Reply", "回复"))
                    .font(Tokens.Font.body(Tokens.Overlay.labelMedium, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(emphasised ? Tokens.Overlay.canvas : Tokens.Overlay.textPrimary)
                    .padding(.leading, 8)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!controller.allowsLessonAction(.reply))
            .background(LessonAnchorReader(anchor: .reply, controller: controller))
            .cursor(.pointingHand)
            DismissCopiedReplyButton(onDismiss: controller.dismissReply, inverted: emphasised, compactLabelSpacing: true)
        }
        .background(Capsule().fill(emphasised ? Tokens.Overlay.textPrimary
            : hovering ? Tokens.Overlay.controlHover : Tokens.Overlay.surface))
        .onHover { hovering = $0 }
        .opacity(controller.lesson != nil && !emphasised ? 0.35 : 1)
    }
}

private struct DismissCopiedReplyButton: View {
    let onDismiss: () -> Void
    var inverted = false
    var compactLabelSpacing = false
    @State private var hovering = false

    var body: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(inverted ? Tokens.Overlay.canvas
                    : hovering ? Tokens.Overlay.textPrimary : Tokens.Overlay.textSecondary)
                .offset(x: compactLabelSpacing ? -4 : 0)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(tr("返信に使うコピーを閉じる", "Dismiss copied reply context", "关闭已复制的回复内容"))
        .help(tr("クリップボードの内容は残ります", "Keeps the text on your clipboard", "不会清空剪贴板"))
        .cursor(.pointingHand)
    }
}

private struct CopiedReplyHeader: View {
    let source: ReplySource
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.turn.up.left")
                .font(.system(size: 11))
                .accessibilityHidden(true)
            Text(source.contextText)
                .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(source.contextText)
                .accessibilityLabel(tr("返信する文章：", "Replying to: ", "回复内容：") + source.contextText)
            DismissCopiedReplyButton(onDismiss: onDismiss)
        }
        .foregroundStyle(Tokens.Overlay.textSecondary)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 34)
    }
}

/// The free-text path, in both of its modes.
///
/// The target was already captured — when ✎ was pressed for a rewrite, and when Reply was clicked
/// for a reply (§16) — so this field is safe to make key either way.
struct InputBar: View {
    @ObservedObject var controller: OverlayController
    @State private var text = ""
    @State private var lessonID: UUID?
    @FocusState private var focused: Bool

    private var isReply: Bool {
        if case .explicitReply = controller.state { return true }
        if case .replyInput = controller.state { return true }
        return false
    }

    /// What the instruction will actually be applied to (§18).
    ///
    /// This is the one place the user can be told, and it is the reason they were being
    /// misled: the bar asked 「どう書き換えますか？」 over an empty compose box and over a
    /// desktop with nothing focused at all, so 「もっと丁寧に」 was a reasonable thing to
    /// type and a rewrite of nothing was the reasonable result.
    private var scope: RewriteScope? {
        switch controller.state {
        case .explicitReply(let captured), .inputBar(let captured), .replyInput(_, let captured):
            return captured.target.scope
        case .pill, .hoverRow, .generating, .result:
            return nil
        }
    }

    /// Empty submits are allowed in reply mode and blocked in rewrite mode. There is
    /// no rewrite without an instruction, but "just write me a reply" is a request —
    /// `OverlayController.defaultReplyInstruction` is what actually goes over the wire.
    ///
    /// A scratch compose (§18) stays blocked for the strongest version of the same
    /// reason: with no source text *and* no instruction there is nothing to send at all.
    private var canSubmit: Bool {
        if let session = controller.replySession {
            return (session.phase == .loading || session.phase == .ready) && session.queuedGuidance == nil
        }
        return isReply || !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Rendered separately from the field. AppKit's native placeholder ignores the
    /// overlay foreground in a non-activating panel and follows the system appearance,
    /// which can put black text on this always-dark bar.
    private var placeholderText: String {
        // Reply mode names itself, and its scope is always the message that was copied
        // rather than anything in the field — §16's whole point.
        if isReply {
            return tr(
                "返信の指示（空欄でおまかせ）",
                "Reply instructions (optional)",
                "回复要求（可留空）"
            )
        }
        switch scope {
        case .scratch:
            // Nothing to rewrite: either the field is empty or there is no field. Asking
            // *what to write* is what stops an instruction being typed at nothing.
            return tr("何を書きますか？", "What should I write?", "要写什么？")
        case .selection:
            return tr(
                "選択した文章をどう書き換えますか？",
                "How should the selected text be rewritten?",
                "选中的文字要怎么改写？"
            )
        case .inputField, .none:
            return tr("どう書き換えますか？", "How should this be rewritten?", "想怎么改写？")
        }
    }

    var body: some View {
        let sidebar = controller.usesSidebarLayout
        let layout = sidebar
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            BrandMark(animation: .engaged)

            ZStack(alignment: sidebar ? .topLeading : .leading) {
                if text.isEmpty {
                    Text(placeholderText)
                        .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
                        .foregroundStyle(Tokens.Overlay.textSecondary)
                        .lineLimit(sidebar ? nil : 1)
                        .allowsHitTesting(false)
                }

                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
                    .foregroundStyle(Tokens.Overlay.textPrimary)
                    .lineLimit(1...(sidebar ? Tokens.Geometry.sideInputMaxLines : Tokens.Geometry.inputBarMaxLines))
                    .focused($focused)
                    .disabled(controller.replySession?.queuedGuidance != nil)
                    .accessibilityLabel(placeholderText)
                    .onSubmit { controller.submitInput(text) }
            }
            .padding(sidebar ? 10 : 0)
            .frame(maxWidth: .infinity,
                   minHeight: sidebar ? Tokens.Geometry.sideEditorHeight : nil,
                   maxHeight: sidebar ? Tokens.Geometry.sideEditorHeight : nil,
                   alignment: sidebar ? .topLeading : .leading)
            .background {
                if sidebar {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Tokens.Overlay.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Tokens.Overlay.hairline, lineWidth: 1)
                        }
                }
            }
            .layoutPriority(1)
            .background(LessonAnchorReader(anchor: .composer, controller: controller))

            Button {
                controller.submitInput(text)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: sidebar ? 22 : 17))
                    .foregroundStyle(
                        canSubmit ? Tokens.Overlay.textPrimary : Tokens.Overlay.textTertiary
                    )
                    .frame(width: sidebar ? 28 : nil, height: sidebar ? 28 : nil)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel(tr("生成", "Generate", "生成"))
            .cursor(canSubmit ? .pointingHand : .arrow)
            .frame(maxWidth: sidebar ? .infinity : nil, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, sidebar ? 12 : 8)
        .frame(width: sidebar ? Tokens.Geometry.sideInputWidth : Tokens.Geometry.inputBarWidth)
        .onAppear { lessonID = controller.lesson?.id; focused = true }
        .onChange(of: text) { _, value in controller.guidanceChanged(value, sessionID: lessonID) }
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
        /// ended so the selected slot can be committed (§4).
        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            onDragEnded?()
        }
    }
}
