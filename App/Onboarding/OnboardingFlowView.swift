import AppKit
import AVFoundation
import DesktopRewriteKit
import SwiftUI

struct OnboardingFlowView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        ZStack {
            Tokens.Window.shell
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ProgressRail(step: coordinator.step)
                    .padding(.horizontal, OnboardingMetrics.pagePadding)
                    .padding(.top, 28)
                    .padding(.bottom, 18)

                Group {
                    switch coordinator.step {
                    case .welcome: WelcomeStep(coordinator: coordinator)
                    case .purpose: PurposeStep(coordinator: coordinator)
                    case .review: ButtonReviewStep(coordinator: coordinator)
                    case .access: AccessStep(coordinator: coordinator)
                    case .bar: BarStep(coordinator: coordinator)
                    case .practice: PracticeStep(coordinator: coordinator)
                    case .customPractice: CustomPracticeStep(coordinator: coordinator)
                    case .replyPractice: ReplyPracticeStep(coordinator: coordinator)
                    case .source: SourceStep(coordinator: coordinator)
                    case .complete: CompleteStep(coordinator: coordinator)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingNavigationBar(coordinator: coordinator)
            }
            .background(Tokens.Window.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Window.panelRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 1)
            .padding(4)
        }
        .ignoresSafeArea()
        .onExitCommand {
            if coordinator.step != .welcome { coordinator.back() }
        }
    }
}

private enum OnboardingMetrics {
    static let pagePadding: CGFloat = 48
    static let contentWidth: CGFloat = 920
    static let contentTopPadding: CGFloat = 8
    static let bottomPadding: CGFloat = 12
    static let navigationHeight: CGFloat = 58
    static let visualVerticalInset: CGFloat = 10
}

private struct OnboardingNavigationBar: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var model: MainModel

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        self.model = coordinator.mainModel
    }

    var body: some View {
        VStack(spacing: 0) {
            Hairline()

            HStack(spacing: 12) {
                if coordinator.step != .welcome && coordinator.step != .complete {
                    LinkButton(title: "戻る") { coordinator.back() }
                }

                Spacer()

                switch coordinator.step {
                case .welcome:
                    if model.isSignedIn {
                        primaryButton(
                            coordinator.isPreparingPurpose ? "ボタンを読み込み中…" : "続ける",
                            enabled: !coordinator.isPreparingPurpose
                        )
                    }

                case .purpose:
                    primaryButton("このセットを確認")

                case .review:
                    primaryButton(
                        coordinator.isSavingButtons ? "保存中…" : "保存して続ける",
                        enabled: coordinator.canConfirmButtons && !coordinator.isSavingButtons
                    )

                case .access:
                    if model.isTrusted {
                        primaryButton("続ける")
                    } else {
                        ActionButton("システム設定を開く", style: .secondary) {
                            openAccessibilitySettings()
                        }
                        ActionButton("許可する") { model.requestAccessibility() }
                    }

                case .bar:
                    LinkButton(title: "あとで始める") { coordinator.skipEducation() }
                    primaryButton("書き換えを練習")

                case .practice:
                    LinkButton(title: "あとで始める") { coordinator.skipEducation() }
                    primaryButton("カスタムも練習", enabled: coordinator.rewritePracticeCompleted)

                case .customPractice:
                    LinkButton(title: "あとで始める") { coordinator.skipEducation() }
                    primaryButton("返信も練習", enabled: coordinator.customPracticeCompleted)

                case .replyPractice:
                    LinkButton(title: "あとで始める") { coordinator.skipEducation() }
                    primaryButton("次へ", enabled: coordinator.replyPracticeCompleted)

                case .source:
                    LinkButton(title: "答えない") { coordinator.skipSource() }
                    primaryButton("次へ", enabled: coordinator.selectedSource != nil)

                case .complete:
                    primaryButton("敬語ボタンを使う")
                }
            }
            .frame(height: OnboardingMetrics.navigationHeight)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
    }

    @ViewBuilder
    private func primaryButton(_ title: String, enabled: Bool = true) -> some View {
        ActionButton(title, enabled: enabled) { coordinator.advance() }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ProgressRail: View {
    let step: DesktopOnboardingStep

    private let labels: [DesktopOnboardingStep: String] = [
        .welcome: "アカウント",
        .purpose: "用途",
        .review: "ボタン",
        .access: "アクセス",
        .practice: "書き換え",
        .customPractice: "カスタム",
        .replyPractice: "返信",
        .source: "きっかけ",
        .complete: "完了",
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(DesktopOnboardingStep.flow.enumerated()), id: \.element) { index, item in
                let currentIndex = DesktopOnboardingStep.flow.firstIndex(of: step) ?? 0
                let isCurrent = item == step
                VStack(alignment: .leading, spacing: 7) {
                    Group {
                        if item == .bar {
                            PillPreview(scale: 0.52)
                        } else {
                            Text(labels[item] ?? "")
                                .font(Tokens.Font.body(11, weight: isCurrent ? .medium : .regular))
                                .foregroundStyle(
                                    index <= currentIndex
                                        ? Tokens.Window.accentText
                                        : Tokens.Window.textTertiary
                                )
                        }
                    }
                    .frame(height: 15, alignment: .leading)
                    Capsule()
                        .fill(index <= currentIndex ? Tokens.Window.accent : Tokens.Window.hairline)
                        .frame(height: 3)
                }
            }
        }
    }
}

private struct WelcomeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var model: MainModel
    @State private var showsEmail = false

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        self.model = coordinator.mainModel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    AppMark(size: 20)
                        .opticalCentre()
                    Text("敬語ボタン")
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                }

                Text("書きたいことを、\nどこでも整える。")
                    .font(Tokens.Font.display(26))
                    .tracking(Tokens.Font.displayTracking(26))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .padding(.top, 24)

                Text("入力中の文章を、その場に合う言葉へ。\nボタンを選ぶだけで、同じ場所へ戻せます。")
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .lineSpacing(5)
                    .padding(.top, 12)

                Group {
                    if model.isSignedIn {
                        connectedContent
                    } else {
                        authenticationContent
                    }
                }
                .padding(.top, 24)
            }
            .frame(width: 400, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingMascotHero()
                    .frame(width: 344, height: 344)
                    .mask {
                        RoundedRectangle(cornerRadius: 44, style: .continuous)
                            .padding(10)
                            .blur(radius: 16)
                    }
                    .padding(28)
            }
            .padding(.vertical, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card(padding: 16, radius: 12) {
                HStack(spacing: 12) {
                    StatusDot(ok: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("アカウントに接続済み")
                            .font(Tokens.Font.body(14, weight: .medium))
                            .foregroundStyle(Tokens.Window.textPrimary)
                        Text(model.signedInEmail ?? "")
                            .font(Tokens.Font.body(12))
                            .foregroundStyle(Tokens.Window.textSecondary)
                    }
                }
            }
            if let error = coordinator.purposeError {
                Text(error)
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var authenticationContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            GoogleSignInButton(isLoading: model.isAuthenticating) {
                model.signInWithGoogle()
            }

            HStack(spacing: 12) {
                Hairline()
                Text("または")
                    .font(Tokens.Font.body(11))
                    .foregroundStyle(Tokens.Window.textTertiary)
                Hairline()
            }

            if showsEmail {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsField(placeholder: "メールアドレス", text: $model.email)
                    SettingsField(placeholder: "パスワード", text: $model.password, secure: true)
                    if model.authMode == .signUp {
                        SettingsField(placeholder: "パスワード（確認）", text: $model.passwordConfirm, secure: true)
                    }

                    if let error = model.authError {
                        Text(error)
                            .font(Tokens.Font.body(12))
                            .foregroundStyle(Tokens.Window.textPrimary)
                    }
                    if let notice = model.authNotice {
                        Text(notice)
                            .font(Tokens.Font.body(12))
                            .foregroundStyle(Tokens.Window.textSecondary)
                    }

                    HStack(spacing: 12) {
                        ActionButton(
                            model.authMode == .signIn ? "サインイン" : "アカウントを作成",
                            enabled: canSubmit
                        ) {
                            if model.authMode == .signIn { model.signIn() } else { model.signUp() }
                        }
                        LinkButton(
                            title: model.authMode == .signIn ? "新規登録" : "サインインへ"
                        ) {
                            model.authMode = model.authMode == .signIn ? .signUp : .signIn
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showsEmail = true }
                } label: {
                    Text("メールアドレスで続ける")
                        .font(Tokens.Font.body(13, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.Window.canvas))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Tokens.Window.hairline))
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
            }
        }
    }

    private var canSubmit: Bool {
        !model.isAuthenticating && model.email.contains("@") && model.password.count >= 6
    }
}

private struct GoogleSignInButton: View {
    let isLoading: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image("GoogleG")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 18, height: 18)
                Text(isLoading ? "接続中…" : "Google で続ける")
                    .font(Tokens.Font.body(14, weight: .medium))
                    .foregroundStyle(Color(hex: 0x1f1f1f))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Tokens.Window.surface : .white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(hex: 0x747775), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .onHover { hovering = $0 }
        .cursor(isLoading ? .arrow : .pointingHand)
    }
}

private struct PurposeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    private var model: MainModel { coordinator.mainModel }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 22) {
                StepHeading(
                    eyebrow: "ボタンを選ぶ",
                    title: "主にどこで使いますか？",
                    subtitle: "用途に合う4つを用意します。次の画面で名前も指示も変更できます。"
                )

                HStack(alignment: .top, spacing: 10) {
                    Icon(.info, size: 14)
                        .foregroundStyle(Tokens.Window.accentText)
                        .opticalCentre()
                    Text("ここで選ぶのは出発点です。名前、順番、AIへの指示は次の画面で自由に調整できます。")
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 250, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            OnboardingVisualStage {
                GeometryReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            if !model.prompts.isEmpty {
                                PurposeOptionCard(
                                    title: "現在のボタンを使う",
                                    caption: "iPhoneと同期している設定をそのまま確認",
                                    titles: model.prompts.prefix(4).map(\.title),
                                    selected: coordinator.usesCurrentButtons
                                ) {
                                    coordinator.selectCurrentButtons()
                                }
                            }

                            ForEach(OnboardingPresetPack.allCases, id: \.rawValue) { pack in
                                PurposeOptionCard(
                                    title: pack.title,
                                    caption: pack.caption,
                                    titles: pack.buttonTitles,
                                    selected: coordinator.selectedPack == pack
                                ) {
                                    coordinator.select(pack: pack)
                                }
                            }
                        }
                        .padding(18)
                        .frame(minHeight: proxy.size.height, alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.vertical, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }
}

private struct PurposeOptionCard: View {
    let title: String
    let caption: String
    let titles: [String]
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(Tokens.Font.body(14, weight: .medium))
                            .foregroundStyle(Tokens.Window.textPrimary)
                        Text(caption)
                            .font(Tokens.Font.body(12))
                            .foregroundStyle(Tokens.Window.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    ZStack {
                        Circle()
                            .strokeBorder(selected ? Tokens.Window.accent : Tokens.Window.controlOff, lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                        if selected {
                            Circle().fill(Tokens.Window.accent).frame(width: 10, height: 10)
                        }
                    }
                }

                HStack(spacing: 6) {
                    ForEach(titles, id: \.self) { title in
                        Text(title)
                            .font(Tokens.Font.body(11, weight: .medium))
                            .foregroundStyle(selected ? Tokens.Window.accentText : Tokens.Window.textSecondary)
                            .opticalPadding(vertical: 3, horizontal: 7)
                            .background(
                                Capsule().fill(selected ? Tokens.Window.accentPlate : Tokens.Window.surface)
                            )
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering && !selected ? Tokens.Window.surface : Tokens.Window.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Tokens.Window.accent : Tokens.Window.hairline, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
    }
}

/// The one page whose left column is a working list rather than a paragraph, and the
/// three rules that keep it from behaving like one.
///
/// 1. **The block is vertically centred**, like every other split page. That is only
///    possible if the column has a natural height, and a `ScrollView` never does — it
///    takes everything it is offered. So the list is capped at the height its rows
///    occupy *collapsed* (`listViewportHeight`) and stays flexible below that, which
///    makes it exactly as tall as its content when the set is short and lets the parent
///    compress it when the set is long.
/// 2. **Opening a row cannot resize anything outside the list.** The cap is computed
///    from the row count, not measured from the content, so an expanded editor grows
///    *inside* a viewport that does not move: the heading, the 追加 action and the whole
///    right column stay exactly where they were. The expanded row is scrolled to the top
///    of that viewport in the same animation, which is where the editor is legible.
/// 3. **The preview column is a layout invariant** (§15). It spans the full height on
///    its own terms and reads nothing about the left column. It used to flip its
///    alignment from centre to top whenever a row opened, so pressing ✎ moved the one
///    thing on screen the user had not touched.
private struct ButtonReviewStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var editingID: UUID?

    /// Enforced on the collapsed row rather than assumed of it — `ButtonDraftRow` sets
    /// this as an explicit height, so the arithmetic below cannot drift from what is
    /// drawn. 74 is what the two 26 pt reorder buttons plus the row's padding measured.
    private static let rowHeight: CGFloat = 74
    private static let rowSpacing: CGFloat = 10

    /// The list's height with every row closed. `+ 2` is the 1 pt inset the rows are
    /// padded by so their focus rings and borders are not clipped by the scroll view.
    private var listViewportHeight: CGFloat {
        let count = CGFloat(coordinator.buttonDrafts.count)
        return count * Self.rowHeight + max(0, count - 1) * Self.rowSpacing + 2
    }

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ScrollViewReader { scroll in
                VStack(alignment: .leading, spacing: 18) {
                    StepHeading(
                        eyebrow: "ボタンを確認",
                        title: "使うボタンを確認",
                        subtitle: "先頭がメインボタンです。名前、指示、順番はここで変更できます。"
                    )

                    ScrollView {
                        VStack(spacing: Self.rowSpacing) {
                            ForEach(Array(coordinator.buttonDrafts.enumerated()), id: \.element.id) { index, draft in
                                ButtonDraftRow(
                                    draft: draft,
                                    index: index,
                                    count: coordinator.buttonDrafts.count,
                                    height: Self.rowHeight,
                                    isEditing: editingID == draft.id,
                                    onToggleEdit: { toggleEdit(of: draft.id, scroll: scroll) },
                                    onChange: coordinator.updateDraft,
                                    onMove: { coordinator.moveDraft(id: draft.id, by: $0) },
                                    onDelete: {
                                        if editingID == draft.id { editingID = nil }
                                        coordinator.deleteDraft(id: draft.id)
                                    }
                                )
                                .id(draft.id)
                            }
                        }
                        .padding(1)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: listViewportHeight)

                    if coordinator.buttonDrafts.count < 7 {
                        ActionButton("ボタンを追加", icon: .add, style: .secondary) {
                            coordinator.addDraft()
                        }
                    }
                }
                .frame(width: 540, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 16) {
                PillCaption(suffix: "のプレビュー")

                OnboardingBarPreview(titles: coordinator.buttonDrafts.map(\.title))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text("一番上のボタンは、iPhoneでもメインとして表示されます。")
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = coordinator.reviewError {
                    Text(error)
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }

    /// One gesture, one motion: the row grows and the list scrolls it to the top under
    /// the same curve. The editor itself only fades — sliding it in from the top edge as
    /// well described the same event twice, against a row that was already growing.
    private func toggleEdit(of id: UUID, scroll: ScrollViewProxy) {
        let opening = editingID != id
        withAnimation(.easeOut(duration: 0.18)) {
            editingID = opening ? id : nil
            if opening { scroll.scrollTo(id, anchor: .top) }
        }
    }
}

private struct ButtonDraftRow: View {
    let draft: OnboardingButtonDraft
    let index: Int
    let count: Int
    /// The closed row's height, fixed so `ButtonReviewStep` can size the list's viewport
    /// from the row count alone and keep it stable while a row is open.
    let height: CGFloat
    let isEditing: Bool
    let onToggleEdit: () -> Void
    let onChange: (OnboardingButtonDraft) -> Void
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    IconButton(icon: .arrowUp, help: "上へ", enabled: index > 0) { onMove(-1) }
                    IconButton(icon: .arrowDown, help: "下へ", enabled: index < count - 1) { onMove(1) }
                }
                .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(draft.title.isEmpty ? "名称未設定" : draft.title)
                            .font(Tokens.Font.body(14, weight: .medium))
                            .foregroundStyle(Tokens.Window.textPrimary)
                        if index == 0 { Badge("メイン") }
                    }
                    Text(draft.prompt.isEmpty ? "指示を入力してください" : draft.prompt)
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 10)
                IconButton(icon: .edit, help: "編集") { onToggleEdit() }
                IconButton(icon: .trash, help: "削除", enabled: count > 1) { onDelete() }
            }
            .padding(.horizontal, 14)
            .frame(height: height)

            if isEditing {
                Hairline()
                VStack(alignment: .leading, spacing: 10) {
                    SectionCaption(text: "ボタン名")
                    SettingsField(
                        placeholder: "ボタン名",
                        text: Binding(
                            get: { draft.title },
                            set: { value in
                                var next = draft
                                next.title = String(value.prefix(12))
                                onChange(next)
                            }
                        )
                    )

                    SectionCaption(text: "AIへの指示")
                    TextEditor(text: Binding(
                        get: { draft.prompt },
                        set: { value in
                            var next = draft
                            next.prompt = value
                            onChange(next)
                        }
                    ))
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 82)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.Window.group))
                }
                .padding(14)
                .transition(.opacity)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.Window.canvas))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Tokens.Window.hairline))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct OnboardingBarPreview: View {
    let titles: [String]

    var body: some View {
        OnboardingVisualStage {
            OnboardingMailScene(labels: titles.map { $0.isEmpty ? "未設定" : $0 }) {
                OnboardingStaticMailBody(text: "明日の会議を15時に変更していただけますか。")
            }
        }
    }
}

private struct AccessStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var model: MainModel

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        self.model = coordinator.mainModel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 24) {
                StepHeading(
                    eyebrow: "必要な設定",
                    title: "文章を読み、同じ場所へ戻すために",
                    subtitle: "アクセシビリティは、いま選ばれている入力欄だけを読み書きするために必要です。マイクと画面収録は使いません。"
                )

                Card(padding: 18) {
                    HStack(spacing: 14) {
                        IconPlate(icon: .accessibility, diameter: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("アクセシビリティ")
                                .font(Tokens.Font.body(14, weight: .medium))
                                .foregroundStyle(Tokens.Window.textPrimary)
                            Text(model.isTrusted ? "許可済みです" : "システム設定で敬語ボタンを許可してください")
                                .font(Tokens.Font.body(12))
                                .foregroundStyle(Tokens.Window.textSecondary)
                        }
                        Spacer()
                        StatusDot(ok: model.isTrusted)
                    }
                }

            }
            .frame(width: 350, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            PermissionIllustration(granted: model.isTrusted)
                .padding(.vertical, OnboardingMetrics.visualVerticalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }

}

private struct BarStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var model: MainModel

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        self.model = coordinator.mainModel
    }

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            VStack(alignment: .leading, spacing: 24) {
                PillStepHeading()

                VStack(alignment: .leading, spacing: 14) {
                    TeachingPillRow(number: "01", suffix: "にカーソルを合わせて開く")
                    TeachingRow(number: "02", text: "ラベルを押して書き換える")
                    TeachingRow(number: "03", text: "結果を確認して置き換え")
                    TeachingRow(number: "04", text: "自由な指示をその場で入力")
                }

            }
            .frame(width: 350, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            BarIllustration(prompts: model.prompts.enabledForHoverRow)
                .padding(.vertical, OnboardingMetrics.visualVerticalInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }
}

private struct PracticeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var sample: String
    @State private var focused = true

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        _sample = State(initialValue: coordinator.tutorialSample)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom, spacing: 28) {
                PracticeStepHeading(
                    completed: coordinator.rewritePracticeCompleted
                )
                .frame(maxWidth: 560, alignment: .leading)

                Spacer(minLength: 0)

                PracticeStatusBadge(
                    completed: coordinator.rewritePracticeCompleted,
                    pendingText: "結果が出たら書き換える",
                    completedText: "書き戻し完了"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingMailScene(labels: [], showsBar: false) {
                    OnboardingPracticeEditor(
                        text: $sample,
                        isFocused: $focused,
                        fontSize: 15,
                        accessibilityLabel: "練習用メッセージ"
                    )
                    .background(.white)
                }
            }
            .padding(.bottom, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }
}

private struct CustomPracticeStep: View {
    private static let sourceDraft = "明日の15時の打ち合わせですが、資料の準備が間に合わないので、来週火曜日の同じ時間に変更したいです。"
    private static let suggestedGuidance = "取引先向けに、簡潔なメールにしてください。"

    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var draft = Self.sourceDraft
    @State private var focused = true

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom, spacing: 28) {
                CustomPracticeHeading(completed: coordinator.customPracticeCompleted)
                    .frame(maxWidth: 590, alignment: .leading)

                Spacer(minLength: 0)

                if coordinator.customPracticeCompleted {
                    PracticeStatusBadge(
                        completed: true,
                        pendingText: "",
                        completedText: "カスタム指示で書き戻しました"
                    )
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("入力例")
                            .font(Tokens.Font.body(10, weight: .medium))
                            .foregroundStyle(Tokens.Window.textTertiary)
                        Text(Self.suggestedGuidance)
                            .font(Tokens.Font.body(11, weight: .medium))
                            .foregroundStyle(Tokens.Window.accentText)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.Window.accentTint))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingMailScene(labels: [], showsBar: false) {
                    OnboardingPracticeEditor(
                        text: $draft,
                        isFocused: $focused,
                        fontSize: 15,
                        accessibilityLabel: "カスタム練習用メッセージ"
                    )
                    .background(.white)
                }
            }
            .padding(.bottom, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }
}

private struct ReplyPracticeStep: View {
    private static let sourceMessage = "明日の15時からのプロジェクト定例、参加できそうですか？"

    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var reply = ""
    @State private var copied = false
    @State private var focused = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom, spacing: 28) {
                ReplyPracticeHeading(completed: coordinator.replyPracticeCompleted)
                    .frame(maxWidth: 640, alignment: .leading)

                Spacer(minLength: 0)

                PracticeStatusBadge(
                    completed: coordinator.replyPracticeCompleted,
                    pendingText: "例：参加できると丁寧に",
                    completedText: "返信を書き戻しました"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingSlackScene(
                    message: Self.sourceMessage,
                    copied: copied,
                    onCopy: copyMessage
                ) {
                    OnboardingPracticeEditor(
                        text: $reply,
                        isFocused: $focused,
                        fontSize: 13,
                        contentInset: NSSize(width: 14, height: 12),
                        placeholder: "# product への返信",
                        accessibilityLabel: "返信練習用メッセージ"
                    )
                    .background(.white)
                }
            }
            .padding(.bottom, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }

    private func copyMessage() {
        coordinator.copyReplyPracticeMessage(Self.sourceMessage)
        copied = true
        focused = true
    }
}

private struct PracticeStatusBadge: View {
    let completed: Bool
    let pendingText: String
    let completedText: String

    var body: some View {
        HStack(spacing: 7) {
            Icon(completed ? .check : .info, size: 13)
                .opticalCentre()
            Text(completed ? completedText : pendingText)
                .font(Tokens.Font.body(11, weight: .medium))
        }
        .foregroundStyle(completed ? Tokens.Window.success : Tokens.Window.accentText)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Capsule().fill(completed ? Tokens.Window.surface : Tokens.Window.accentTint))
    }
}

private struct OnboardingPracticeEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var fontSize: CGFloat
    var contentInset = NSSize(width: 14, height: 16)
    var placeholder: String?
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = PracticeNSTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = contentInset
        textView.font = editorFont
        textView.textColor = NSColor(red: 0x4e / 255, green: 0x4d / 255, blue: 0x51 / 255, alpha: 1)
        textView.insertionPointColor = NSColor(red: 0x5a / 255, green: 0x57 / 255, blue: 0xba / 255, alpha: 1)
        textView.string = text
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        focusIfNeeded(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PracticeNSTextView else { return }
        context.coordinator.parent = self
        textView.font = editorFont
        textView.textContainerInset = contentInset
        textView.placeholder = placeholder
        textView.setAccessibilityLabel(accessibilityLabel)
        if textView.string != text { textView.string = text }
        focusIfNeeded(textView)
        textView.needsDisplay = true
    }

    private var editorFont: NSFont {
        NSFont(name: "Inter", size: fontSize) ?? .systemFont(ofSize: fontSize)
    }

    private func focusIfNeeded(_ textView: NSTextView) {
        guard isFocused else { return }
        DispatchQueue.main.async { [weak textView] in
            guard let textView, textView.window?.firstResponder !== textView else { return }
            textView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: OnboardingPracticeEditor
        weak var textView: NSTextView?

        init(_ parent: OnboardingPracticeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
        }
    }

    final class PracticeNSTextView: NSTextView {
        var placeholder: String?

        override func draw(_ dirtyRect: NSRect) {
            if string.isEmpty, let placeholder, !placeholder.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font ?? NSFont.systemFont(ofSize: 13),
                    .foregroundColor: NSColor(red: 0xb3 / 255, green: 0xb3 / 255, blue: 0xb8 / 255, alpha: 1),
                ]
                placeholder.draw(at: textContainerOrigin, withAttributes: attributes)
            }
            super.draw(dirtyRect)
        }
    }
}

/// 「どこで知りましたか？」 — the one page of first run that asks for something rather
/// than teaching something, so it deliberately reuses 用途's exact composition: the same
/// question-left / choice-grid-right split, the same card metrics, the same selection
/// dot. It is a question, not a gate — 「答えない」 sits beside the forward action.
private struct SourceStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 22) {
                StepHeading(
                    eyebrow: "最後にひとつ",
                    title: "敬語ボタンをどこで知りましたか？",
                    subtitle: "どこで見つけてもらえたのかを知るためだけの質問です。近いものを1つ選んでください。"
                )

                HStack(alignment: .top, spacing: 10) {
                    Icon(.info, size: 14)
                        .foregroundStyle(Tokens.Window.accentText)
                        .opticalCentre()
                    Text("送るのは選んだ項目だけです。答えずに進んでも、機能は何も変わりません。")
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 250, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            OnboardingVisualStage {
                GeometryReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(OnboardingSource.allCases, id: \.self) { source in
                                SourceOptionCard(
                                    source: source,
                                    selected: coordinator.selectedSource == source
                                ) {
                                    coordinator.select(source: source)
                                }
                            }
                        }
                        .padding(18)
                        .frame(minHeight: proxy.size.height, alignment: .center)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.vertical, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }
}

private struct SourceOptionCard: View {
    let source: OnboardingSource
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                SourceMark(source: source)
                Text(source.label)
                    .font(Tokens.Font.body(13, weight: .medium))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Tokens.Window.accent : Tokens.Window.controlOff, lineWidth: 1.5)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle().fill(Tokens.Window.accent).frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering && !selected ? Tokens.Window.surface : Tokens.Window.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Tokens.Window.accent : Tokens.Window.hairline, lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
    }
}

/// The four app sources carry their real App Store artwork; the rest are Reicon on a
/// plate, the same pairing the sign-in page already makes when it puts the official
/// Google G beside the app's own glyphs (§15).
private struct SourceMark: View {
    let source: OnboardingSource

    private let size: CGFloat = 28
    /// Apple's icon superellipse. The artwork is delivered square, so the mask belongs
    /// here rather than baked into an asset that would then be wrong at another size.
    private var radius: CGFloat { size * 0.2237 }

    var body: some View {
        switch source {
        case .x: brand("SourceX")
        case .youtube: brand("SourceYouTube")
        case .instagram: brand("SourceInstagram")
        case .tiktok: brand("SourceTikTok")
        case .webSearch: IconPlate(icon: .search, diameter: size, tinted: false)
        case .friend: IconPlate(icon: .user, diameter: size, tinted: false)
        case .article: IconPlate(icon: .window, diameter: size, tinted: false)
        case .other: IconPlate(icon: .info, diameter: size, tinted: false)
        }
    }

    private func brand(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08))
            )
    }
}

private struct CompleteStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        HStack(alignment: .top, spacing: 40) {
            VStack(alignment: .leading, spacing: 24) {
                IconPlate(icon: .check, diameter: 48)
                CompleteStepHeading()
                VStack(alignment: .leading, spacing: 10) {
                    CompletionRow(text: "アカウントとボタンを同期")
                    CompletionRow(text: "アクセシビリティを許可")
                    CompletionRow(text: "書き換えの操作を確認")
                    CompletionRow(text: "一度だけのカスタム指示を確認")
                    CompletionRow(text: "コピーから返信する操作を確認")
                }
            }
            .frame(width: 380, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingMailScene(labels: coordinator.mainModel.prompts.enabledForHoverRow.map(\.title)) {
                    OnboardingStaticMailBody(
                        text: "恐れ入りますが、明日の会議を15時に変更していただけますでしょうか。",
                        focused: false
                    )
                }
            }
            .padding(.vertical, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }
}

private struct StepHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(eyebrow)
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(title)
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            Text(subtitle)
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PillCaption: View {
    let suffix: String

    var body: some View {
        HStack(spacing: 6) {
            PillPreview(scale: 0.52)
            Text(suffix)
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.textTertiary)
        }
    }
}

private struct PillStepHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("いつもの使い方")
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            HStack(spacing: 8) {
                Text("画面下の")
                PillPreview(scale: 0.72)
                Text("が待っています")
            }
            .font(Tokens.Font.display(20))
            .tracking(Tokens.Font.displayTracking(20))
            .foregroundStyle(Tokens.Window.textPrimary)
            .lineLimit(1)
            HStack(spacing: 6) {
                Text("入力欄に文章を置いたまま、")
                PillPreview(scale: 0.58)
                Text("へカーソルを移動。")
            }
            .font(Tokens.Font.body(14))
            .foregroundStyle(Tokens.Window.textSecondary)
            Text("入力欄のフォーカスは失われません。")
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textSecondary)
        }
    }
}

private struct PracticeStepHeading: View {
    let completed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("実際に試す")
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(completed ? "書き戻せました" : "選んだボタンで試してみましょう")
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            if completed {
                Text("いまの操作が、ほかのアプリでも同じように使えます。")
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
            } else {
                HStack(spacing: 6) {
                    Text("本文にフォーカスを残し、")
                    PillPreview(scale: 0.58)
                    Text("を開いて、好きなボタンを押します。")
                }
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textSecondary)
            }
        }
    }
}

private struct ReplyPracticeHeading: View {
    let completed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("返信を試す")
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(completed ? "返信を書き戻せました" : "コピーしたメッセージに返信してみましょう")
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            if completed {
                Text("コピーから返信まで、実際の操作で完了しました。")
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
            } else {
                HStack(spacing: 6) {
                    Text("メッセージをコピーし、返信欄にフォーカスしたまま")
                    PillPreview(scale: 0.58)
                    Text("を開きます。")
                }
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textSecondary)
            }
        }
    }
}

private struct CustomPracticeHeading: View {
    let completed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("カスタム指示を試す")
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(completed ? "一度だけの指示で書き戻せました" : "このメールだけの仕上げ方を伝えましょう")
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            if completed {
                Text("保存済みのボタンを変えずに、その場だけの指示を使えます。")
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
            } else {
                HStack(spacing: 6) {
                    Text("本文にフォーカスを残し、")
                    PillPreview(scale: 0.58)
                    Text("を開いて右端の ✎ を押します。")
                }
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textSecondary)
                Text("✎ は、その書き換えに一度だけ使う指示を入力するボタンです。入力後に生成し、結果を入れ替えてください。")
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CompleteStepHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("セットアップ完了")
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text("準備できました")
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            HStack(spacing: 6) {
                Text("文章にフォーカスを置き、画面下の")
                PillPreview(scale: 0.58)
                Text("を開くだけです。")
            }
            .font(Tokens.Font.body(14))
            .foregroundStyle(Tokens.Window.textSecondary)
            Text("ウインドウを閉じても、敬語ボタンはメニューバーと画面下に残ります。")
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TeachingRow: View {
    let number: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(Tokens.Font.mono(12))
                .foregroundStyle(Tokens.Window.accentText)
                .frame(width: 22, alignment: .leading)
            Text(text).font(Tokens.Font.body(14)).foregroundStyle(Tokens.Window.textPrimary)
        }
    }
}

private struct TeachingPillRow: View {
    let number: String
    let suffix: String

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(Tokens.Font.mono(12))
                .foregroundStyle(Tokens.Window.accentText)
                .frame(width: 22, alignment: .leading)
            HStack(spacing: 6) {
                PillPreview(scale: 0.58)
                Text(suffix)
            }
            .font(Tokens.Font.body(14))
            .foregroundStyle(Tokens.Window.textPrimary)
        }
    }
}

private struct CompletionRow: View {
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Icon(.check, size: 14)
                .foregroundStyle(Tokens.Window.success)
                .opticalCentre()
            Text(text)
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textPrimary)
        }
    }
}

private struct OnboardingMascotHero: View {
    var compact = false

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "OnboardingMascotLoop", withExtension: "mp4") {
                LoopingVideoView(url: url)
            } else {
                Image(Icon.Name.markFilled)
                    .resizable()
                    .scaledToFit()
                    .padding(compact ? 76 : 82)
            }
        }
        .frame(width: compact ? 360 : 400, height: compact ? 360 : 400)
    }
}

private struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> LoopingPlayerView {
        LoopingPlayerView(url: url)
    }

    func updateNSView(_ view: LoopingPlayerView, context: Context) {}

    static func dismantleNSView(_ view: LoopingPlayerView, coordinator: ()) {
        view.stop()
    }

    final class LoopingPlayerView: NSView {
        private let queue = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()

        init(url: URL) {
            super.init(frame: .zero)
            wantsLayer = true
            playerLayer.player = queue
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            queue.isMuted = true
            queue.play()
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layout() {
            super.layout()
            playerLayer.frame = bounds
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window == nil ? queue.pause() : queue.play()
        }

        func stop() {
            queue.pause()
            looper?.disableLooping()
            looper = nil
        }
    }
}

private struct PermissionIllustration: View {
    let granted: Bool
    var body: some View {
        OnboardingVisualStage {
            OnboardingSystemSettingsScene(granted: granted)
        }
    }
}

private struct BarIllustration: View {
    let prompts: [UserPrompt]
    private var labels: [String] {
        let titles = prompts.prefix(4).map(\.title)
        return titles.isEmpty ? ["敬語", "自然に", "メール", "英訳"] : titles
    }

    var body: some View {
        OnboardingVisualStage {
            OnboardingMailScene(labels: labels) {
                OnboardingStaticMailBody(text: "明日の会議、15時に変更しといて")
            }
        }
    }
}

private extension Array where Element == UserPrompt {
    var enabledForHoverRow: [UserPrompt] {
        let main = filter { $0.slot == .main && $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        let sub = filter { $0.slot == .sub && $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        return main + sub
    }
}
