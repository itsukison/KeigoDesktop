import AppKit
import DesktopRewriteKit
import SwiftUI

/// §4: may become key, and only after the target has already been captured.
/// Enter = Insert, Esc = dismiss.
final class ResultPanel: NSPanel {

    private let context: CurrentValueBox<ResultContext>

    private let geometry: CurrentValueBox<CompanionGeometry>
    private var measuredHeight: CGFloat = Tokens.Geometry.resultPanelMaxHeight

    init(geometry: CompanionGeometry, controller: OverlayController, context: ResultContext) {
        let box = CurrentValueBox(context)
        self.context = box
        self.geometry = CurrentValueBox(geometry)
        super.init(
            contentRect: geometry.frame(size: NSSize(width: geometry.resultWidth, height: geometry.resultMaxHeight)),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )

        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true          // §8 deviation 1, drawn outside the frame
        isMovableByWindowBackground = false
        animationBehavior = .none

        let hostingView = NSHostingView(
            rootView: ResultView(controller: controller, box: box, geometry: self.geometry) { [weak self] height in
                self?.applyContentHeight(height)
            }
        )
        // `applyContentHeight` is the sole owner of this window's frame. Leaving
        // `.standardBounds` enabled lets a conditional SwiftUI subtree (most notably
        // the no-destination notice) resize the panel behind the controller's back
        // during its first presentation.
        hostingView.sizingOptions = []
        contentView = hostingView
    }

    /// Reused rather than rebuilt when only the pager index changed — recreating the
    /// window would drop key status and flash.
    func update(context: ResultContext) {
        self.context.value = context
    }

    func reanchor(_ geometry: CompanionGeometry) {
        self.geometry.value = geometry
        applyContentHeight(measuredHeight)
    }

    func applyContentHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        measuredHeight = height
        let placement = geometry.value
        let size = NSSize(width: placement.resultWidth,
                          height: min(height, placement.resultMaxHeight))
        let target = placement.frame(size: size)
        guard target != frame else { return }
        setFrame(target, display: true)
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

struct ResultView: View {
    @ObservedObject var controller: OverlayController
    @ObservedObject var box: CurrentValueBox<ResultContext>
    @ObservedObject var geometry: CurrentValueBox<CompanionGeometry>
    let onHeightChange: (CGFloat) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var appeared = false
    @State private var topHeight: CGFloat = 50
    @State private var bottomHeight: CGFloat = 90
    @State private var bodyBottom: CGFloat = 0

    @State private var refinementText: String = ""
    @State private var showsRefinement = false
    @State private var refinementHovered = false
    @State private var refinementCloseTask: Task<Void, Never>?
    @FocusState private var refinementFocused: Bool
    /// The result text's own height, before any clamping. Only meaningful next to
    /// `bodyHeight`: the two differing is exactly what "the body overflows" means.
    @State private var bodyIntrinsic: CGFloat = 0
    /// The label held still while the pointer is over the footer.
    ///
    /// The destination is re-read twice a second and the primary button is labelled from
    /// it, so without this the button can change what it does in the ~100 ms between
    /// someone deciding to click and clicking. Frozen on entry, released on exit — and
    /// `InsertIntent` makes the press honour what was frozen rather than what the probe
    /// has since decided.
    @State private var frozenAction: InsertAction?

    private var action: InsertAction { frozenAction ?? controller.insertAction }

    private var context: ResultContext { box.value }

    private var zone: SnapZone { geometry.value.zone }
    private var bodyHeight: CGFloat {
        let available = max(0, geometry.value.resultMaxHeight - topHeight - bottomHeight)
        return min(max(bodyIntrinsic, Tokens.Geometry.resultBodyMinHeight), geometry.value.resultBodyMaxHeight, available)
    }
    private var overflows: Bool { bodyIntrinsic > bodyHeight + 0.5 }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ResultTopHeightKey.self, value: proxy.size.height)
            })
            body_
            VStack(spacing: 0) {
                notice
                footer
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: ResultBottomHeightKey.self, value: proxy.size.height)
            })
        }
        .frame(width: geometry.value.resultWidth)
        .clipShape(zone.companionShape())
        .opacity(appeared ? 1 : 0.85)
        // Keep the native backdrop outside SwiftUI's content clipping and fade.
        // SmokedGlassSurface masks its own visual-effect view to this shape.
        .background(SmokedGlassSurface(
            shape: zone.companionShape(), joinsNotch: zone == .topCenter, showsBorder: false
        ))
        .overlay(zone.companionShape().strokeBorder(
            contrast == .increased ? Tokens.Overlay.textSecondary : Tokens.Overlay.hairline, lineWidth: 1)
            .mask(ExposedPanelEdges(zone: zone)))
        .background(GeometryReader { proxy in
            Color.clear.preference(key: PanelHeightKey.self, value: proxy.size.height)
        })
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: zone.companionAlignment)
        .onPreferenceChange(PanelHeightKey.self, perform: onHeightChange)
        .onPreferenceChange(ResultTopHeightKey.self) { topHeight = $0 }
        .onPreferenceChange(ResultBottomHeightKey.self) { bottomHeight = $0 }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) { appeared = true }
        }
        .onChange(of: context.selectedIndex) { _, _ in
            hideRefinement()
        }
        .onDisappear { refinementCloseTask?.cancel() }
        .onExitCommand { escape() }
    }

    private func escape() {
        if showsRefinement { hideRefinement() }
        else { controller.dismiss() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
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

            Spacer()
            Button { controller.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Tokens.Overlay.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(QuietOverlayButtonStyle())
            .accessibilityLabel(tr("閉じる", "Close", "关闭"))
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
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietOverlayButtonStyle())
        .accessibilityLabel(symbol == "chevron.left" ? tr("前の結果", "Previous result", "上一个结果") : tr("次の結果", "Next result", "下一个结果"))
        .disabled(!enabled)
        // §14's rule, and it applies to the overlay too: a disabled control keeps the
        // arrow. With one page both pager arrows are dead, and a hand over them would
        // be promising a page that is not there.
        .cursor(enabled ? .pointingHand : .arrow)
    }

    // MARK: Body

    private var body_: some View {
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
                            .preference(key: ResultBodyBottomKey.self, value: proxy.frame(in: .named("resultBody")).maxY)
                    }
                )
        }
        .coordinateSpace(name: "resultBody")
        .scrollIndicators(.never)
        .scrollDisabled(!overflows)
        .frame(height: bodyHeight)
        .mask {
            if overflows && bodyBottom > bodyHeight + 1 {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white.opacity(0.85), location: 0.5),
                        .init(color: .white.opacity(0.45), location: 0.75),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 64)
                }
            } else {
                Rectangle()
            }
        }
        .onPreferenceChange(BodyHeightKey.self) { bodyIntrinsic = $0 }
        .onPreferenceChange(ResultBodyBottomKey.self) { bodyBottom = $0 }
        .id(context.selectedIndex)
    }

    // MARK: Notice

    // Reserve the localized notice's measured height so destination polling cannot move actions.
    private var notice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
            Text(tr(
                "入力欄が選択されていません。コピーするか、入力欄を選んで挿入。",
                "No input field is focused. Copy, or focus one to Insert.",
                "光标当前不在输入框中。可以复制文本，或先点击输入框再插入。"
            ))
            .font(Tokens.Font.body(Tokens.Overlay.labelMedium))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Tokens.Overlay.textSecondary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .opacity(action == .copyOnly ? 1 : 0)
        .accessibilityHidden(action != .copyOnly)
    }

    // MARK: Footer

    private var footer: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                standardFooterRow
                    .accessibilityHidden(showsRefinement)
                    .opacity(showsRefinement ? 0 : 1)
                    .allowsHitTesting(!showsRefinement)

                refinementBar(availableWidth: proxy.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 28)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: showsRefinement)
    }

    private var standardFooterRow: some View {
        HStack(spacing: 6) {
            // `refinementBar` supplies ↻ in its collapsed state. This spacer keeps the
            // remaining actions in their original positions without leaving a second,
            // invisible regenerate button in keyboard or accessibility navigation.
            Color.clear.frame(width: 28, height: 28)
            // Dropped when the primary *is* Copy. Two controls that do the same thing,
            // one of them labelled and one of them an icon, only raise the question of
            // how they differ.
            if action != .copyOnly {
                footerButton("doc.on.doc", label: tr("コピー", "Copy", "复制")) { controller.copyToClipboard() }
            }
            footerButton("hand.thumbsup", label: tr("良い結果", "Good result", "好结果")) { controller.vote(up: true) }
            footerButton("hand.thumbsdown", label: tr("良くない結果", "Poor result", "不好的结果")) { controller.vote(up: false) }

            Spacer()

            // One button, three jobs, and the label is the whole fix (§18): whichever of
            // them this press will do is decided from a live read of the destination
            // before it is pressed, not discovered after the text has gone nowhere.
            // Enter stays bound to it in all three, because it is still the one thing
            // to do with a result.
            Button { controller.insert(intent: action == .copyOnly ? .copy : .write) } label: {
                HStack(spacing: 6) {
                    Text(insertLabel)
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
            .keyboardShortcut(showsRefinement ? KeyboardShortcut?.none : .defaultAction)
            .cursor(.pointingHand)
            .help(insertHelp)
            .background(LessonAnchorReader(anchor: .result, controller: controller))
        }
        // Freezing the whole row, not just the button: the pointer has to cross the row
        // to reach the button, and a label that changes on the way there is the same
        // surprise one frame earlier.
        .onHover { hovering in
            frozenAction = hovering ? controller.insertAction : nil
        }
    }

    private var insertLabel: String {
        switch action {
        case .insert, .insertHere: return tr("挿入", "Insert", "插入")
        case .copyOnly: return tr("コピー", "Copy", "复制")
        }
    }

    /// Why the button says what it says. The label carries the action; this carries the
    /// reason, which is the part a user who never saw the original field disappear needs.
    private var insertHelp: String {
        switch action {
        case .insert:
            return tr(
                "元の入力欄に書き戻します。",
                "Writes it back into the original field.",
                "写回原来的输入框。"
            )
        case .insertHere:
            return tr(
                "元の入力欄は選択が外れています。いまカーソルがある入力欄に挿入します。",
                "The original field lost focus. This inserts into the field you're in now.",
                "原输入框已失去焦点。将插入到当前光标所在的输入框。"
            )
        case .copyOnly:
            return tr(
                "書き込める入力欄がありません。コピーして、貼り付けたい場所で ⌘V を押してください。",
                "There's no field to write into. Copy it, then press ⌘V where you want it.",
                "没有可写入的输入框。请复制后在需要的位置按 ⌘V。"
            )
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
                            : Color.clear)
                        .frame(width: showsRefinement ? 20 : 28,
                               height: showsRefinement ? 20 : 28)
                )
            }
            .buttonStyle(QuietOverlayButtonStyle())
            .accessibilityLabel(showsRefinement ? tr("送信", "Send", "发送") : tr("再生成", "Regenerate", "重新生成"))
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
                .fill(showsRefinement ? Tokens.Overlay.surface : Color.clear)
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

    private func footerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Tokens.Overlay.textSecondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(QuietOverlayButtonStyle())
        .accessibilityLabel(label)
        .help(label)
        .cursor(.pointingHand)
    }

    private func revealRefinement() {
        refinementCloseTask?.cancel()
        refinementCloseTask = nil
        guard !showsRefinement else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { showsRefinement = true }
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { showsRefinement = false }
    }

    private func submitRefinement() {
        let instruction = refinementText.trimmingCharacters(in: .whitespacesAndNewlines)
        if instruction.isEmpty {
            controller.regenerate()
        } else {
            controller.refine(instruction: instruction)
        }
    }


}


private struct ResultTopHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct ResultBottomHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct ResultBodyBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct QuietOverlayButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(
                enabled && (hovered || focused || configuration.isPressed) ? Tokens.Overlay.surface : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                focused ? Tokens.Overlay.textSecondary : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}

struct ExposedPanelEdges: View {
    let zone: SnapZone
    var body: some View {
        Rectangle().padding(.top, zone == .topCenter ? 1 : 0)
            .padding(.leading, zone == .left ? 1 : 0)
            .padding(.trailing, zone == .right ? 1 : 0)
    }
}
