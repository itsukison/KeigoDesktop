import DesktopRewriteKit
import SwiftUI

struct WhatsNewModal: View {
    let version: String
    var initialPage = 0
    var initialDemoStep = 0
    let onDismiss: () -> Void
    let onOpenButtons: () -> Void

    var body: some View {
        ZStack {
            Tokens.Window.scrim.ignoresSafeArea().onTapGesture(perform: onDismiss)
            WhatsNewCard(version: version, initialPage: initialPage, initialDemoStep: initialDemoStep,
                         onDismiss: onDismiss, onOpenButtons: onOpenButtons)
        }
        .onExitCommand(perform: onDismiss)
        .background {
            Button("", action: onDismiss).keyboardShortcut(.cancelAction).hidden()
        }
    }
}

struct WhatsNewCard: View {
    let version: String
    let onDismiss: () -> Void
    let onOpenButtons: () -> Void
    @State private var page: Int
    @State private var demoStep: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var nextFocused: Bool

    init(version: String, initialPage: Int = 0, initialDemoStep: Int = 0,
         onDismiss: @escaping () -> Void, onOpenButtons: @escaping () -> Void) {
        self.version = version
        self.onDismiss = onDismiss
        self.onOpenButtons = onOpenButtons
        _page = State(initialValue: min(max(initialPage, 0), ReleaseHighlights.features.count - 1))
        _demoStep = State(initialValue: initialDemoStep)
    }

    private var feature: ReleaseFeature { ReleaseHighlights.features[page] }
    private var lastPage: Bool { page == ReleaseHighlights.features.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                AppMark(size: 24)
                Text(tr("アップデートのご案内", "What's new", "更新亮点"))
                    .font(Tokens.LightFont.body(14, weight: .semibold))
                Text(version == "preview" ? tr("プレビュー", "Preview", "预览") : "v\(version)").font(Tokens.LightFont.body(12)).foregroundStyle(Tokens.Window.textSecondary)
                Spacer()
                RoundIconButton(icon: .close, help: tr("閉じる", "Close", "关闭"), action: onDismiss)
            }
            .padding(.horizontal, 28).frame(height: 64)

            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 18) {
                    Text(feature.label)
                        .font(Tokens.LightFont.body(12, weight: .medium))
                        .foregroundStyle(feature.ink)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(feature.tint, in: Capsule())
                    Text(feature.title)
                        .font(Tokens.LightFont.display(28, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(feature.detail)
                        .font(Tokens.LightFont.body(14))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(feature.tip)
                        .font(Tokens.LightFont.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if feature == .buttons {
                        Button(action: onOpenButtons) {
                            HStack(spacing: 6) {
                                Text(tr("ボタンを編集する", "Edit your buttons", "编辑按钮"))
                                Text("↗")
                            }.font(Tokens.LightFont.body(13, weight: .medium))
                        }
                        .buttonStyle(.plain).foregroundStyle(Tokens.Window.accentText)
                        .cursor(.pointingHand)
                    }
                }
                .padding(.vertical, 12)
                .frame(width: 264, height: 376, alignment: .topLeading)

                ReleaseDemo(feature: feature, step: $demoStep)
                    .frame(width: 436, height: 376)
                    .id(feature)
            }
            .padding(.horizontal, 28)

            ZStack {
                HStack(spacing: 12) {
                    if page > 0 {
                        Button(tr("戻る", "Back", "返回")) { move(to: page - 1) }
                            .buttonStyle(.plain).font(Tokens.LightFont.body(13))
                            .foregroundStyle(Tokens.Window.textSecondary).cursor(.pointingHand)
                    } else {
                        Text(tr("新しい使い方を、ひとつずつ。", "Small changes. New possibilities.", "一点新变化，更多可能。"))
                            .font(Tokens.LightFont.body(12)).foregroundStyle(Tokens.Window.textSecondary)
                    }
                    Spacer()
                    ActionButton(lastPage ? tr("使ってみる", "Done", "开始使用") : tr("次へ", "Next", "下一步"), style: .primary) {
                        if lastPage { onDismiss() } else { move(to: page + 1) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .focused($nextFocused)
                }
                HStack(spacing: 6) {
                    ForEach(ReleaseHighlights.features.count > 1 ? Array(ReleaseHighlights.features.indices) : [], id: \.self) { index in
                        Button { move(to: index) } label: {
                            Capsule().fill(index == page ? Tokens.Window.accentText : Tokens.Window.controlOff)
                                .frame(width: index == page ? 22 : 6, height: 6)
                                .frame(minWidth: 24, minHeight: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).cursor(.pointingHand)
                        .accessibilityLabel(ReleaseHighlights.features[index].label)
                        .accessibilityValue(tr("\(index + 1) / \(ReleaseHighlights.features.count)",
                                              "\(index + 1) of \(ReleaseHighlights.features.count)",
                                              "第 \(index + 1) 页，共 \(ReleaseHighlights.features.count) 页"))
                        .accessibilityAddTraits(index == page ? .isSelected : [])
                    }
                }
            }
            .padding(.horizontal, 28).frame(height: 100)
        }
        .foregroundStyle(Tokens.Window.textPrimary)
        .frame(width: 780, height: 540)
        .background(Tokens.Window.canvas, in: RoundedRectangle(cornerRadius: 20))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.14), radius: 28, y: 10)
        .onAppear { nextFocused = true }
    }

    private func move(to index: Int) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            page = index
            demoStep = 0
        }
    }
}

private extension ReleaseFeature {
    var ink: Color {
        switch self {
        case .buttons: return Tokens.Window.accentText
        case .placement: return Color(hex: 0xa03a69)
        case .reply: return Color(hex: 0x99501d)
        }
    }
    var tint: Color {
        switch self {
        case .buttons: return Color(hex: 0xe5f4fe)
        case .placement: return Color(hex: 0xfbe7f0)
        case .reply: return Color(hex: 0xffeddc)
        }
    }
}

private struct ReleaseDemo: View {
    let feature: ReleaseFeature
    @Binding var step: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stageLabel: String {
        switch feature {
        case .buttons:
            return step == 0 ? tr("1. メールの下書き", "1. A draft email", "1. 邮件草稿") : tr("2. ボタンひとつで丁寧に", "2. One tap to make it polite", "2. 一键变得更礼貌")
        case .placement: return tr("この中でバーをドラッグしてみましょう", "Try dragging the bar inside this preview", "在演示中拖动工具栏，试试看")
        case .reply:
            return step == 0 ? tr("1. メッセージをコピー", "1. Copy a message", "1. 复制消息") : tr("2. 返信欄から「返信」へ", "2. Focus the reply field, then Reply", "2. 点击回复输入框，再选择「回复」")
        }
    }

    var body: some View {
        ZStack {
            AsideBackdrop(artwork: .mountain)
            VStack(spacing: 0) {
                HStack {
                    Text(tr("使い方プレビュー", "HOW IT WORKS", "使用演示"))
                        .font(Tokens.LightFont.body(10, weight: .semibold)).tracking(1)
                    Spacer()
                    Text(String(format: "%02d", (ReleaseHighlights.features.firstIndex(of: feature) ?? 0) + 1))
                        .font(Tokens.LightFont.mono(11))
                }
                .foregroundStyle(Color(hex: 0x334d5b)).padding(20)
                Spacer(minLength: 0)
                switch feature {
                case .buttons: styleScene
                case .placement: placementScene
                case .reply: replyScene
                }
                Spacer(minLength: 0)
                VStack(spacing: 9) {
                    Text(stageLabel).font(Tokens.LightFont.body(12, weight: .medium))
                        .multilineTextAlignment(.center)
                    if feature != .placement {
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { step = step == 0 ? 1 : 0 }
                        } label: {
                            HStack(spacing: 6) {
                                Icon(step == 0 ? .arrowUp : .history, size: 13)
                                Text(step == 0 ? tr("続きを見る", "Show next step", "查看下一步") : tr("もう一度見る", "Replay", "再看一次"))
                            }
                            .font(Tokens.LightFont.body(12, weight: .medium))
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(.white, in: Capsule())
                        }.buttonStyle(.plain).cursor(.pointingHand)
                    }
                }
                .foregroundStyle(Tokens.Window.textPrimary)
                .frame(height: 82).padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var styleScene: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                sceneHeader(tr("メール", "Email", "邮件"), icon: .noteAdd)
                Text(tr("明日の打ち合わせ", "Tomorrow's meeting", "明天的会议"))
                    .font(Tokens.LightFont.body(13, weight: .semibold))
                Text(step == 0
                     ? tr("明日、資料送ってもらえる？\n会議の前に見ておきたいです。", "Can you send the slides tomorrow?\nI'd like to read them before we meet.", "明日、資料送ってもらえる？\n会議の前に見ておきたいです。")
                     : tr("明日、資料をお送りいただけますか。\n会議の前に確認できれば幸いです。", "Could you send the slides tomorrow?\nI'd appreciate a chance to review them before our meeting.", "明日、資料をお送りいただけますか。\n会議の前に確認できれば幸いです。"))
                    .font(Tokens.LightFont.body(13)).lineSpacing(5)
                    .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
                HStack(spacing: 5) {
                    Icon(step == 0 ? .sliders : .check, size: 12)
                    Text(tr("保存した指示：丁寧にする", "Saved instruction: make it polite", "已保存的指令：让语气更礼貌"))
                        .font(Tokens.LightFont.body(11, weight: .medium))
                }
                .foregroundStyle(Tokens.Window.accentText)
            }
            .padding(18).frame(width: 342).background(.white, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
            miniBar(reply: false)
        }
        .accessibilityElement(children: .combine)
    }

    private var placementScene: some View {
        ReleasePlacementDemo(previewDragging: step == 1)
    }

    private var replyScene: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                sceneHeader(tr("メッセージ", "Messages", "消息"), icon: .copy)
                Text(tr("明日の15時はいかがですか？", "Would 3 pm tomorrow work for you?", "明日の15時はいかがですか？"))
                    .font(Tokens.LightFont.body(13)).lineSpacing(4)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(feature.tint, in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Text(step == 0 ? "⌘C" : tr("返信欄をクリック", "Click the reply field", "点击回复输入框"))
                    Spacer()
                    Icon(step == 0 ? .copy : .check, size: 13)
                }
                .font(Tokens.LightFont.body(12, weight: .medium))
                .foregroundStyle(feature.ink)
            }.padding(18).frame(width: 342)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
            if step == 0 {
                miniBar(reply: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("返信元：明日の15時はいかがですか？", "Replying to: Would 3 pm tomorrow work?", "回复：明日の15時はいかがですか？"))
                        .font(Tokens.LightFont.body(10)).foregroundStyle(Color(hex: 0xa59f97))
                    HStack {
                        Text(tr("大丈夫です、と伝える", "Say that works for me", "告诉对方可以"))
                            .font(Tokens.LightFont.body(12)).foregroundStyle(.white)
                        Spacer()
                        Icon(.arrowUp, size: 14).foregroundStyle(.white)
                    }
                }.padding(12).frame(width: 342)
                    .background(Color(hex: 0x141312), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func sceneHeader(_ title: String, icon: Icon.Name) -> some View {
        HStack(spacing: 6) {
            Icon(icon, size: 13)
            Text(title).font(Tokens.LightFont.body(11, weight: .medium))
            Spacer()
            Circle().fill(feature.tint).frame(width: 8, height: 8)
        }.foregroundStyle(Tokens.Window.textSecondary)
    }

    private func miniBar(reply: Bool) -> some View {
        HStack(spacing: 14) {
            Image(Icon.Name.markFilled).resizable().scaledToFit().frame(width: 17, height: 17)
            Text(tr("敬語", "Polite", "敬语"))
            if reply {
                Text(tr("返信", "Reply", "回复"))
            }
            Icon(.edit, size: 13)
        }
        .font(Tokens.LightFont.body(12, weight: .medium)).foregroundStyle(.white)
        .padding(.horizontal, 16).frame(height: 34)
        .background(Color(hex: 0x141312), in: Capsule())
    }
}

/// A local rehearsal of the real picker; never moves the user's actual bar.
private struct ReleasePlacementDemo: View {
    let previewDragging: Bool
    @State private var zone = 0
    @State private var location: CGPoint?
    @State private var hovered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let size = CGSize(width: 380, height: 224)
    private func anchor(_ index: Int) -> CGPoint {
        switch index {
        case 0: return CGPoint(x: 190, y: 211)
        case 1: return CGPoint(x: 190, y: 13)
        case 2: return CGPoint(x: 10, y: 112)
        default: return CGPoint(x: 370, y: 112)
        }
    }
    private func name(_ index: Int) -> String {
        switch index {
        case 0: return tr("下", "Bottom", "下方")
        case 1: return tr("上", "Top", "顶部")
        case 2: return tr("左", "Left", "左侧")
        default: return tr("右", "Right", "右侧")
        }
    }
    private func candidate(_ point: CGPoint) -> Int? {
        let nearest = (0..<4).min { a, b in
            hypot(point.x - anchor(a).x, point.y - anchor(a).y) < hypot(point.x - anchor(b).x, point.y - anchor(b).y)
        }!
        let target = anchor(nearest)
        return hypot(point.x - target.x, point.y - target.y) < 68 ? nearest : nil
    }
    private var active: Int? { location == nil && previewDragging ? 3 : hovered }
    private var barLocation: CGPoint { location ?? (previewDragging ? CGPoint(x: 338, y: 112) : anchor(zone)) }

    var body: some View {
        ZStack {
            AsideBackdrop(artwork: .mountain)
            // A small desktop window gives the scrim a familiar visual reference.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { _ in Circle().fill(.black.opacity(0.15)).frame(width: 5, height: 5) }
                }
                ForEach([126.0, 182.0, 152.0], id: \.self) { width in
                    Capsule().fill(.black.opacity(0.10)).frame(width: width, height: 5)
                }
                Spacer(minLength: 0)
            }
            .padding(16).frame(width: 230, height: 124)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            Color.black.opacity(0.64)
            ForEach(0..<4) { index in
                let selected = active == index
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(selected ? 0.38 : 0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(selected ? 0.95 : 0.65), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                    .frame(width: index < 2 ? 86 : (selected ? 40 : 30), height: index < 2 ? (selected ? 38 : 28) : 74)
                    .position(x: index == 2 ? 15 : index == 3 ? 365 : 190,
                              y: index == 0 ? 210 : index == 1 ? 14 : 112)
                    .accessibilityHidden(true)
            }
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: 0x141312))
                .frame(width: location != nil || previewDragging || zone < 2 ? 48 : 20,
                       height: location != nil || previewDragging || zone < 2 ? 22 : 44)
                .overlay { Image(Icon.Name.markFilled).resizable().scaledToFit().frame(width: 14, height: 14) }
                .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.24), lineWidth: 1) }
                .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
                .contentShape(Rectangle())
                .position(barLocation)
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("releaseScreen"))
                    .onChanged { value in
                        location = CGPoint(x: min(max(value.location.x, 10), size.width - 10),
                                           y: min(max(value.location.y, 11), size.height - 11))
                        hovered = candidate(value.location)
                    }
                    .onEnded { value in
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86)) {
                            if let destination = candidate(value.location) { zone = destination }
                            location = nil
                            hovered = nil
                        }
                    })
                .cursor(.openHand)
                .accessibilityLabel(tr("プレビューのバー", "Preview bar", "演示工具栏"))
                .accessibilityValue(name(zone))
                .accessibilityAdjustableAction { direction in
                    if direction == .increment { zone = (zone + 1) % 4 }
                    if direction == .decrement { zone = (zone + 3) % 4 }
                }
        }
        .frame(width: size.width, height: size.height)
        .coordinateSpace(name: "releaseScreen")
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.4), lineWidth: 1) }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: active)
    }
}
