import AppKit
import DesktopRewriteKit
import SwiftUI

/// §4: may become key, and only after the target has already been captured.
/// Enter = Insert, Esc = dismiss.
final class ResultPanel: NSPanel {

    private let context: CurrentValueBox<ResultContext>

    init(anchor: NSRect, controller: OverlayController, context: ResultContext) {
        let box = CurrentValueBox(context)
        self.context = box

        let size = NSSize(
            width: Tokens.Geometry.resultPanelWidth,
            height: Tokens.Geometry.resultPanelMaxHeight
        )
        // Takes the bar's place rather than stacking on top of it, per `result.png` —
        // the bar is hidden for the duration — and clamped, because the bar is
        // draggable and 420 pt of card centred on a bar parked near the screen edge
        // used to hang straight off the side.
        super.init(
            contentRect: OverlayPlacement.auxiliaryFrame(size: size, anchoredTo: anchor),
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
        hasShadow = true          // §8 deviation 1, drawn outside the frame
        isMovableByWindowBackground = true
        animationBehavior = .none

        contentView = NSHostingView(
            rootView: ResultView(controller: controller, box: box) { [weak self] height in
                self?.applyContentHeight(height)
            }
        )
    }

    /// Reused rather than rebuilt when only the pager index changed — recreating the
    /// window would drop key status and flash.
    func update(context: ResultContext) {
        self.context.value = context
    }

    /// The window follows SwiftUI's measurement, same as the pill follows its width.
    /// Sizing the panel to a constant is what put a one-line rewrite in the middle of
    /// a 440 pt slab of `canvas`.
    ///
    /// The **bottom** edge stays put so the panel grows upward, away from the screen
    /// edge it is anchored to.
    func applyContentHeight(_ height: CGFloat) {
        let clamped = min(
            max(height, Tokens.Geometry.resultPanelMinHeight),
            Tokens.Geometry.resultPanelMaxHeight
        )
        guard abs(frame.height - clamped) > 0.5 else { return }
        var target = frame
        target.size.height = clamped
        // Not `screen?.visibleFrame`: `NSWindow.screen` is nil once the window is
        // fully off-screen, so the old guard silently skipped the clamp in exactly
        // the case that needed it. And `visibleFrame` still reserves a Dock that may
        // not be there (§4) — `workArea` is the corrected one.
        setFrame(OverlayPlacement.clampToWorkArea(target), display: true)
        invalidateShadow()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// SwiftUI's measured heights, reported up to the panel. `Body` is the text's
/// intrinsic height (which decides whether the scroll fade is warranted at all);
/// `Panel` is the assembled card.
private struct BodyHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Minimal observable box. The panel outlives any single `ResultContext`, and
/// `OverlayController.state` is the source of truth, so this only mirrors it.
final class CurrentValueBox<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

/// Layout per `result.png`: pager + ✕ header, the submitted prompt echoed in an
/// editable field, scrollable body with a bottom fade, footer with
/// regenerate / copy / 👍 / 👎 and a primary `Insert ⏎`.
///
/// Not copied: their `Rewrite F1 + F2` chip — that is a push-to-talk dictation
/// binding and has no meaning here.
struct ResultView: View {
    @ObservedObject var controller: OverlayController
    @ObservedObject var box: CurrentValueBox<ResultContext>
    let onHeightChange: (CGFloat) -> Void

    @State private var promptEcho: String = ""
    @State private var refinementText: String = ""
    @State private var showsRefinement = false
    @State private var refinementHovered = false
    @State private var refinementCloseTask: Task<Void, Never>?
    @FocusState private var refinementFocused: Bool
    /// The result text's own height, before any clamping. Only meaningful next to
    /// `bodyHeight`: the two differing is exactly what "the body overflows" means.
    @State private var bodyIntrinsic: CGFloat = 0

    private var context: ResultContext { box.value }

    private var bodyHeight: CGFloat {
        min(
            max(bodyIntrinsic, Tokens.Geometry.resultBodyMinHeight),
            Tokens.Geometry.resultBodyMaxHeight
        )
    }

    private var overflows: Bool {
        bodyIntrinsic > Tokens.Geometry.resultBodyMaxHeight + 0.5
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            promptField
            body_
            footer
        }
        .background(
            RoundedRectangle(cornerRadius: Tokens.Overlay.panelRadius, style: .continuous)
                .fill(Tokens.Overlay.canvas)
        )
        // The footer paints its own `canvas` background to sit under the hairline, and
        // that rectangle is square — it was covering the rounded background's two
        // bottom corners, so the card read as rounded on top and cut off at the
        // bottom. Clipping the assembled card is what actually gives it four corners.
        .clipShape(
            RoundedRectangle(cornerRadius: Tokens.Overlay.panelRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Overlay.panelRadius, style: .continuous)
                .strokeBorder(Tokens.Overlay.hairline, lineWidth: 1)
        )
        // Elevation comes from `hasShadow` on the window, not from here — see
        // `PillPanel` for why a SwiftUI shadow only produces corner smears.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
            }
        )
        // Takes exactly its ideal height instead of stretching to whatever the window
        // currently is, and sits on the window's bottom edge for the one layout pass
        // before the window catches up — the edge it is anchored to anyway.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .onPreferenceChange(PanelHeightKey.self) { height in
            onHeightChange(height)
        }
        .onAppear { promptEcho = context.selectedPage?.pending.promptText ?? "" }
        .onChange(of: context.selectedIndex) { _, _ in
            // Each regenerated page can carry a different refinement instruction.
            // The echoed prompt must travel with the body when the pager moves.
            promptEcho = context.selectedPage?.pending.promptText ?? ""
        }
        .onDisappear { refinementCloseTask?.cancel() }
        .onExitCommand {
            if showsRefinement {
                hideRefinement()
            } else {
                controller.dismiss()
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            // Always shown, `1 / 1` included — `result.png` shows the readout with a
            // single candidate. It is not only a pager: every regeneration appends a
            // page, so the count is also the user's assurance that an earlier answer
            // remains reachable after asking for another one.
            HStack(spacing: 6) {
                pagerButton("chevron.left", enabled: context.selectedIndex > 0) {
                    controller.selectResult(offsetBy: -1)
                }
                Text(context.pagerLabel)
                    .font(Tokens.Font.body(Tokens.Overlay.labelMedium, weight: .medium))
                    .foregroundStyle(Tokens.Overlay.textSecondary)
                    .monospacedDigit()
                pagerButton(
                    "chevron.right",
                    enabled: context.selectedIndex < context.count - 1
                ) {
                    controller.selectResult(offsetBy: 1)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Capsule().fill(Tokens.Overlay.surface))

            Spacer()

            Button { controller.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tokens.Overlay.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Tokens.Overlay.surface))
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func pagerButton(
        _ symbol: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(enabled ? Tokens.Overlay.textPrimary : Tokens.Overlay.textTertiary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // §14's rule, and it applies to the overlay too: a disabled control keeps the
        // arrow. With one page both pager arrows are dead, and a hand over them would
        // be promising a page that is not there.
        .cursor(enabled ? .pointingHand : .arrow)
    }

    // MARK: Prompt echo

    private var promptField: some View {
        TextField("", text: $promptEcho, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
            .foregroundStyle(Tokens.Overlay.textPrimary)
            .lineLimit(1...3)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
                    .fill(Tokens.Overlay.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
                    .strokeBorder(Tokens.Overlay.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .onSubmit { regenerateWithEditedPrompt() }
    }

    // MARK: Body

    private var body_: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                Text(context.candidate?.replacement ?? "")
                    .font(Tokens.Font.body(Tokens.Overlay.bodySize))
                    .lineSpacing(Tokens.Overlay.bodyLineSpacing)
                    .foregroundStyle(Tokens.Overlay.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: BodyHeightKey.self, value: proxy.size.height)
                        }
                    )
            }
            .scrollIndicators(.never)
            .scrollDisabled(!overflows)
            .frame(height: bodyHeight)

            // Bottom fade, per `result.png` — without it there is no signal that the
            // text continues below the cut. With nothing below the cut it is the
            // opposite: a gradient over empty canvas, which is what `debug.png` shows.
            //
            // `result.png` also has a chevron button sitting in the fade, and **ours is
            // deliberately gone.** It was `allowsHitTesting(false)` decoration: it
            // looked like a button, and clicking it did nothing. The fade already says
            // "there is more below" and the body scrolls, so the chevron was carrying
            // no information the fade wasn't. Restore it only with a scroll-to-bottom
            // action behind it — and then it belongs on top of the fade, not in it.
            //
            // **The fade must be anchored to the viewport's own bottom edge.** It used
            // to sit in a `VStack` above the chevron, which laid the chevron out *below*
            // the gradient and pushed the gradient up by its height (26 + 6 pt). The
            // gradient stopped 32 pt short of the viewport and the last line of text
            // scrolled through that strip at full opacity — text fading out and then
            // reappearing, solid, underneath its own fade. Bottom-aligned in this
            // `ZStack` it terminates exactly where the viewport does.
            //
            // **The stops are eased, not linear.** A straight clear→canvas ramp puts
            // its steepest perceptual change at the top of the band, so it reads as a
            // soft-edged bar laid over the text rather than the text dissolving;
            // holding the alpha low over the first half and letting it run late is what
            // makes it disappear.
            if overflows {
                LinearGradient(
                    stops: [
                        .init(color: Tokens.Overlay.canvas.opacity(0), location: 0),
                        .init(color: Tokens.Overlay.canvas.opacity(0.15), location: 0.5),
                        .init(color: Tokens.Overlay.canvas.opacity(0.55), location: 0.75),
                        .init(color: Tokens.Overlay.canvas, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 64)
                .allowsHitTesting(false)
            }
        }
        .onPreferenceChange(BodyHeightKey.self) { bodyIntrinsic = $0 }
    }

    // MARK: Footer

    private var footer: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                standardFooterRow
                    .opacity(showsRefinement ? 0 : 1)
                    .allowsHitTesting(!showsRefinement)

                refinementBar(availableWidth: proxy.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 28)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Tokens.Overlay.canvas)
        .animation(.easeOut(duration: 0.18), value: showsRefinement)
        // No divider. `result.png` separates the footer from the body with nothing at
        // all — the text simply dissolves into it (see `body_`'s fade). A hairline
        // there read as a table rule across a card that has no other rules on it.
    }

    private var standardFooterRow: some View {
        HStack(spacing: 6) {
            // `refinementBar` supplies ↻ in its collapsed state. This spacer keeps the
            // remaining actions in their original positions without leaving a second,
            // invisible regenerate button in keyboard or accessibility navigation.
            Color.clear.frame(width: 28, height: 28)
            footerButton("doc.on.doc") { controller.copyToClipboard() }
            footerButton("hand.thumbsup") { controller.vote(up: true) }
            footerButton("hand.thumbsdown") { controller.vote(up: false) }

            Spacer()

            Button { controller.insert() } label: {
                HStack(spacing: 6) {
                    Text(tr("挿入", "Insert", "插入"))
                        .font(Tokens.Font.body(Tokens.Overlay.labelLarge, weight: .medium))
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Tokens.Overlay.canvas)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(Capsule().fill(Tokens.Overlay.textPrimary))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .cursor(.pointingHand)
        }
    }

    /// The regenerate control is also the collapsed state of the refinement field.
    /// It owns the same fixed-height footer slot in both states: expansion covers the
    /// other actions instead of asking the result panel (or the text viewport) to move.
    private func refinementBar(availableWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            if showsRefinement {
                ZStack(alignment: .leading) {
                    // AppKit can ignore a SwiftUI `prompt` foreground when a field is
                    // hosted in a non-activating panel and draw it in black. Keep the
                    // field's native placeholder empty and render the hint ourselves,
                    // using the same overlay ramp as the production custom-input bar.
                    if refinementText.isEmpty {
                        Text(refinementPlaceholder)
                            .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
                            .foregroundStyle(Tokens.Overlay.textSecondary)
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $refinementText)
                        .textFieldStyle(.plain)
                        .font(Tokens.Font.body(Tokens.Overlay.labelLarge))
                        .foregroundStyle(Tokens.Overlay.textPrimary)
                        .focused($refinementFocused)
                        .accessibilityLabel(refinementPlaceholder)
                        .onSubmit { submitRefinement() }
                }
                .transition(.opacity)
            }

            Button {
                if showsRefinement {
                    submitRefinement()
                } else {
                    controller.regenerate()
                }
            } label: {
                ZStack {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tokens.Overlay.textSecondary)
                        .opacity(showsRefinement ? 0 : 1)

                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Tokens.Overlay.canvas)
                        .opacity(showsRefinement ? 1 : 0)
                }
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(showsRefinement
                            ? Tokens.Overlay.textPrimary
                            : Tokens.Overlay.surface)
                        .frame(width: showsRefinement ? 20 : 28,
                               height: showsRefinement ? 20 : 28)
                )
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .help(showsRefinement
                ? tr("送信", "Send", "发送")
                : tr(
                    "クリックでそのまま再生成。カーソルを合わせると指示を追加できます。",
                    "Click to regenerate. Hover to add a specific instruction.",
                    "点击直接重新生成，悬停可添加具体要求。"
                ))
        }
        .padding(.leading, showsRefinement ? 10 : 0)
        .frame(
            width: showsRefinement ? availableWidth : 28,
            height: 28,
            alignment: .trailing
        )
        .background(
            RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
                .fill(Tokens.Overlay.surface)
        )
        // Clip only the fill and the contents. Drawing the stroke before this clip
        // shaved its anti-aliased outer pixels during the width animation, which made
        // different corners appear broken from frame to frame.
        .clipShape(
            RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
                .strokeBorder(
                    Tokens.Overlay.hairline.opacity(showsRefinement ? 1 : 0),
                    lineWidth: 1
                )
        )
        .contentShape(
            RoundedRectangle(cornerRadius: Tokens.Overlay.inputRadius, style: .continuous)
        )
        .onHover { hovering in
            refinementHovered = hovering
            hovering ? revealRefinement() : scheduleRefinementClose()
        }
        .onChange(of: refinementFocused) { _, focused in
            focused ? revealRefinement() : scheduleRefinementClose()
        }
        .onKeyPress(.escape) {
            hideRefinement()
            return .handled
        }
    }

    private var refinementPlaceholder: String {
        tr(
            "指示を追加（空欄でそのまま再生成）",
            "Add an instruction (leave blank to regenerate)",
            "添加要求（留空则直接重新生成）"
        )
    }

    private func footerButton(
        _ symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tokens.Overlay.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Tokens.Overlay.surface)
                )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }

    private func revealRefinement() {
        refinementCloseTask?.cancel()
        refinementCloseTask = nil
        guard !showsRefinement else { return }
        withAnimation(.easeOut(duration: 0.16)) { showsRefinement = true }
    }

    private func scheduleRefinementClose() {
        refinementCloseTask?.cancel()
        guard !refinementFocused, !refinementHovered else { return }
        refinementCloseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled, !refinementFocused, !refinementHovered else { return }
            hideRefinement()
        }
    }

    private func hideRefinement() {
        refinementCloseTask?.cancel()
        refinementCloseTask = nil
        refinementFocused = false
        refinementText = ""
        withAnimation(.easeOut(duration: 0.12)) { showsRefinement = false }
    }

    private func submitRefinement() {
        let instruction = refinementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if instruction.isEmpty {
            controller.regenerate()
        } else {
            controller.refine(instruction: instruction)
        }
    }

    /// Editing the echoed prompt and pressing Enter re-runs against the same captured
    /// target — the field is editable in `result.png`, and a field that looks editable
    /// but does nothing is worse than a read-only one.
    private func regenerateWithEditedPrompt() {
        let edited = promptEcho.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !edited.isEmpty else { return }
        controller.regenerate(promptText: edited)
    }
}
