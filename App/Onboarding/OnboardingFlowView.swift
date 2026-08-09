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
                    case .replyPractice: ReplyPracticeStep(coordinator: coordinator)
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
                    primaryButton("返信も練習", enabled: coordinator.rewritePracticeCompleted)

                case .replyPractice:
                    LinkButton(title: "あとで始める") { coordinator.skipEducation() }
                    primaryButton("次へ", enabled: coordinator.replyPracticeCompleted)

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
        .replyPractice: "返信",
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
                    .blendMode(.multiply)
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

private struct ButtonReviewStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var editingID: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                StepHeading(
                    eyebrow: "ボタンを確認",
                    title: "使うボタンを確認",
                    subtitle: "先頭がメインボタンです。名前、指示、順番はここで変更できます。"
                )

                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(coordinator.buttonDrafts.enumerated()), id: \.element.id) { index, draft in
                            ButtonDraftRow(
                                draft: draft,
                                index: index,
                                count: coordinator.buttonDrafts.count,
                                isEditing: editingID == draft.id,
                                onToggleEdit: {
                                    withAnimation(.easeOut(duration: 0.16)) {
                                        editingID = editingID == draft.id ? nil : draft.id
                                    }
                                },
                                onChange: coordinator.updateDraft,
                                onMove: { coordinator.moveDraft(id: draft.id, by: $0) },
                                onDelete: {
                                    if editingID == draft.id { editingID = nil }
                                    coordinator.deleteDraft(id: draft.id)
                                }
                            )
                        }
                    }
                    .padding(1)
                }
                .scrollIndicators(.hidden)

                if coordinator.buttonDrafts.count < 7 {
                    ActionButton("ボタンを追加", icon: .add, style: .secondary) {
                        coordinator.addDraft()
                    }
                }
            }
            .frame(width: 540, alignment: .leading)

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
}

private struct ButtonDraftRow: View {
    let draft: OnboardingButtonDraft
    let index: Int
    let count: Int
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
            .padding(.vertical, 11)

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
                .transition(.opacity.combined(with: .move(edge: .top)))
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
    @FocusState private var focused: Bool

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

                if !coordinator.rewritePracticeCompleted {
                    HStack(spacing: 7) {
                        Icon(.info, size: 13)
                            .opticalCentre()
                        Text("結果が出たら Insert")
                            .font(Tokens.Font.body(11, weight: .medium))
                    }
                    .foregroundStyle(Tokens.Window.accentText)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(Capsule().fill(Tokens.Window.accentTint))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingMailScene(labels: [], showsBar: false) {
                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: $sample)
                            .font(Tokens.Font.body(15))
                            .foregroundStyle(Tokens.Window.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .focused($focused)
                            .background(.white)
                            .accessibilityLabel("練習用メッセージ")

                        if coordinator.rewritePracticeCompleted {
                            HStack(spacing: 5) {
                                Icon(.check, size: 12)
                                    .opticalCentre()
                                Text("書き戻し完了")
                                    .font(Tokens.Font.body(11, weight: .medium))
                            }
                            .foregroundStyle(Tokens.Window.success)
                            .padding(.horizontal, 9)
                            .frame(height: 27)
                            .background(Capsule().fill(.white.opacity(0.94)))
                            .padding(12)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .padding(.bottom, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
        .onAppear { focused = true }
    }
}

private struct ReplyPracticeStep: View {
    private static let sourceMessage = "明日の15時からのプロジェクト定例、参加できそうですか？"

    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var reply = ""
    @State private var copied = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .bottom, spacing: 28) {
                ReplyPracticeHeading(completed: coordinator.replyPracticeCompleted)
                    .frame(maxWidth: 640, alignment: .leading)

                Spacer(minLength: 0)

                if !coordinator.replyPracticeCompleted {
                    HStack(spacing: 7) {
                        Icon(.info, size: 13)
                            .opticalCentre()
                        Text("例：参加できると丁寧に")
                            .font(Tokens.Font.body(11, weight: .medium))
                    }
                    .foregroundStyle(Tokens.Window.accentText)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .background(Capsule().fill(Tokens.Window.accentTint))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingSlackScene(
                    message: Self.sourceMessage,
                    copied: copied,
                    onCopy: copyMessage
                ) {
                    ZStack(alignment: .topLeading) {
                        if reply.isEmpty {
                            Text("# product への返信")
                                .font(Tokens.Font.body(13))
                                .foregroundStyle(Tokens.Window.textTertiary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $reply)
                            .font(Tokens.Font.body(13))
                            .foregroundStyle(Tokens.Window.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .focused($focused)
                            .accessibilityLabel("返信練習用メッセージ")

                        if coordinator.replyPracticeCompleted {
                            HStack(spacing: 5) {
                                Icon(.check, size: 12)
                                    .opticalCentre()
                                Text("返信を書き戻しました")
                                    .font(Tokens.Font.body(11, weight: .medium))
                            }
                            .foregroundStyle(Tokens.Window.success)
                            .padding(.horizontal, 9)
                            .frame(height: 27)
                            .background(Capsule().fill(.white.opacity(0.96)))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .allowsHitTesting(false)
                        }
                    }
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
