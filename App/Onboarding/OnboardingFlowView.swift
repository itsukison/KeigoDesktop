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
                    // Hidden rather than absent on the language page: the rail owns a
                    // fixed slice of a window that cannot resize, and removing it would
                    // move every page down by its height for one step and back up again.
                    .opacity(coordinator.step == .language ? 0 : 1)
                    .padding(.horizontal, OnboardingMetrics.pagePadding)
                    .padding(.top, 28)
                    .padding(.bottom, 18)

                Group {
                    switch coordinator.step {
                    case .language: LanguageStep(coordinator: coordinator)
                    case .welcome: WelcomeStep(coordinator: coordinator)
                    case .purpose: PurposeStep(coordinator: coordinator)
                    case .review: ButtonReviewStep(coordinator: coordinator)
                    case .access: AccessStep(coordinator: coordinator)
                    case .bar: BarStep(coordinator: coordinator)
                    case .practice: PracticeStep(coordinator: coordinator)
                    case .customPractice: CustomPracticeStep(coordinator: coordinator)
                    case .replyPractice: ReplyPracticeStep(coordinator: coordinator)
                    case .source: SourceStep(coordinator: coordinator)
                    case .offer: OfferStep(coordinator: coordinator)
                    case .complete: CompleteStep(coordinator: coordinator)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OnboardingNavigationBar(coordinator: coordinator)
            }
            // `tr` reads a global, so nothing above is invalidated by a language
            // change on its own. Re-identifying the panel rebuilds every step's body
            // at once, which is what makes the picker's effect visible on the page
            // that owns it.
            .id(coordinator.language)
            .background(Tokens.Window.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Window.panelRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 1)
            .padding(4)
        }
        .ignoresSafeArea()
        .onExitCommand {
            if coordinator.step != .language { coordinator.back() }
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
                if coordinator.step != .language && coordinator.step != .complete {
                    LinkButton(title: tr("戻る", "Back", "返回")) { coordinator.back() }
                }

                Spacer()

                switch coordinator.step {
                case .language:
                    primaryButton(tr("続ける", "Continue", "继续"))

                case .welcome:
                    if model.isSignedIn {
                        primaryButton(
                            coordinator.isPreparingPurpose
                                ? tr("ボタンを読み込み中…", "Loading your buttons…", "正在加载按钮…")
                                : tr("続ける", "Continue", "继续"),
                            enabled: !coordinator.isPreparingPurpose
                        )
                    }

                case .purpose:
                    primaryButton(tr("このセットを確認", "Review this set", "确认这组按钮"))

                case .review:
                    primaryButton(
                        coordinator.isSavingButtons
                            ? tr("保存中…", "Saving…", "保存中…")
                            : tr("保存して続ける", "Save and continue", "保存并继续"),
                        enabled: coordinator.canConfirmButtons && !coordinator.isSavingButtons
                    )

                case .access:
                    if model.isTrusted {
                        primaryButton(tr("続ける", "Continue", "继续"))
                    } else {
                        ActionButton(
                            tr("システム設定を開く", "Open System Settings", "打开系统设置"),
                            style: .secondary
                        ) {
                            openAccessibilitySettings()
                        }
                        ActionButton(tr("許可する", "Grant access", "授予权限")) {
                            model.requestAccessibility()
                        }
                    }

                case .bar:
                    LinkButton(title: tr("あとで始める", "Skip for now", "稍后再说")) { coordinator.skipEducation() }
                    primaryButton(tr("書き換えを練習", "Try a rewrite", "练习改写"))

                case .practice:
                    LinkButton(title: tr("あとで始める", "Skip for now", "稍后再说")) { coordinator.skipEducation() }
                    primaryButton(tr("カスタムも練習", "Try a custom one", "练习自定义指令"), enabled: coordinator.rewritePracticeCompleted)

                case .customPractice:
                    LinkButton(title: tr("あとで始める", "Skip for now", "稍后再说")) { coordinator.skipEducation() }
                    primaryButton(tr("返信も練習", "Try a reply", "练习回复"), enabled: coordinator.customPracticeCompleted)

                case .replyPractice:
                    LinkButton(title: tr("あとで始める", "Skip for now", "稍后再说")) { coordinator.skipEducation() }
                    primaryButton(tr("次へ", "Next", "下一步"), enabled: coordinator.replyPracticeCompleted)

                case .source:
                    LinkButton(title: tr("答えない", "Skip", "不回答")) { coordinator.skipSource() }
                    primaryButton(tr("次へ", "Next", "下一步"), enabled: coordinator.selectedSource != nil)

                case .offer:
                    // 「あとで」 until the browser has been handed a checkout, then
                    // 「次へ」. Someone who has already gone to pay is not declining,
                    // and leaving the only forward action labelled as a refusal is the
                    // kind of small dishonesty that makes a purchase feel like a trap.
                    LinkButton(
                        title: coordinator.offerCheckoutOpened
                            ? tr("次へ", "Next", "下一步")
                            : tr("あとで", "Maybe later", "以后再说")
                    ) { coordinator.skipOffer() }
                    primaryButton(
                        model.isOpeningBilling
                            ? tr("開いています…", "Opening…", "正在打开…")
                            : tr("この価格で始める", "Get this price", "以此价格开始"),
                        enabled: coordinator.offerExpiresAt != nil && !model.isOpeningBilling
                    )

                case .complete:
                    primaryButton(tr("敬語ボタンを使う", "Start using KeigoButton", "开始使用敬語ボタン"))
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

    /// Two pages are deliberately **not** segments — `DesktopOnboardingStep.railSteps`
    /// owns which and why. The short version: the language question is asked before
    /// setting up begins, and the welcome offer is a purchase rather than a step of
    /// installation.
    private static let steps = DesktopOnboardingStep.railSteps

    /// A step with no segment of its own lights the last one at or before it, so the
    /// offer page reads as "still at the end of setup" rather than resetting the rail
    /// to segment one — which is what `firstIndex(of:) ?? 0` did.
    private var currentIndex: Int {
        guard let anchor = step.railAnchor else { return 0 }
        return Self.steps.firstIndex(of: anchor) ?? 0
    }

    private var labels: [DesktopOnboardingStep: String] {
        [
            .welcome: tr("アカウント", "Account", "账户"),
            .purpose: tr("用途", "Use", "用途"),
            .review: tr("ボタン", "Buttons", "按钮"),
            .access: tr("アクセス", "Access", "权限"),
            .practice: tr("書き換え", "Rewrite", "改写"),
            .customPractice: tr("カスタム", "Custom", "自定义"),
            .replyPractice: tr("返信", "Reply", "回复"),
            .source: tr("きっかけ", "Source", "来源"),
            .complete: tr("完了", "Done", "完成"),
        ]
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(Self.steps.enumerated()), id: \.element) { index, item in
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
                    Text(tr("敬語ボタン", "KeigoButton", "敬語ボタン"))
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                }

                Text(tr("書きたいことを、\nどこでも整える。", "Write anywhere.\nPolish it in place.", "想写的内容，\n在任何地方都能整理好。"))
                    .font(Tokens.Font.display(26))
                    .tracking(Tokens.Font.displayTracking(26))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .padding(.top, 24)

                Text(tr("入力中の文章を、その場に合う言葉へ。\nボタンを選ぶだけで、同じ場所へ戻せます。", "Turn what you are typing into the right words.\nPress a button and it goes back where it came from.", "把正在输入的文字，换成合适的表达。\n只需按下按钮，就会写回原处。"))
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
                        Text(tr("アカウントに接続済み", "Connected to your account", "已连接账户"))
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
                Text(tr("または", "or", "或"))
                    .font(Tokens.Font.body(11))
                    .foregroundStyle(Tokens.Window.textTertiary)
                Hairline()
            }

            if showsEmail {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsField(placeholder: tr("メールアドレス", "Email address", "邮箱地址"), text: $model.email)
                    SettingsField(placeholder: tr("パスワード", "Password", "密码"), text: $model.password, secure: true)
                    if model.authMode == .signUp {
                        SettingsField(placeholder: tr("パスワード（確認）", "Confirm password", "确认密码"), text: $model.passwordConfirm, secure: true)
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
                            model.authMode == .signIn
                                ? tr("サインイン", "Sign in", "登录")
                                : tr("アカウントを作成", "Create account", "创建账户"),
                            enabled: canSubmit
                        ) {
                            if model.authMode == .signIn { model.signIn() } else { model.signUp() }
                        }
                        LinkButton(
                            title: model.authMode == .signIn
                                ? tr("新規登録", "Create one", "注册")
                                : tr("サインインへ", "Sign in instead", "去登录")
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
                    Text(tr("メールアドレスで続ける", "Continue with email", "使用邮箱继续"))
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

/// The first page, and the only one asked before setup begins.
///
/// It reuses 用途's composition — question left, choices on the lavender stage — rather
/// than inventing a splash screen, for the same reason きっかけ does: a page that looks
/// like a different product's is read as one.
///
/// Two things about it are deliberate. The **option labels are endonyms and are never
/// translated**: a picker that renames 日本語 to "Japanese" in an English UI is unusable
/// by the one person who needs it. And the choice **applies on click, not on 続ける** —
/// this page is where the effect of the choice is visible, so applying it late would
/// leave the user no way to check they picked the right one.
private struct LanguageStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 22) {
                StepHeading(
                    eyebrow: tr("はじめに", "First", "首先"),
                    title: tr("使う言語を選んでください", "Choose your language", "请选择使用的语言"),
                    subtitle: tr(
                        "アプリの表示言語です。あとから設定でいつでも変更できます。",
                        "This sets the app's interface. You can change it any time in Settings.",
                        "这是应用的界面语言。之后可随时在设置中更改。"
                    )
                )

                HStack(alignment: .top, spacing: 10) {
                    Icon(.info, size: 14)
                        .foregroundStyle(Tokens.Window.accentText)
                        .opticalCentre()
                    Text(languageNote)
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 250, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            OnboardingVisualStage {
                VStack(spacing: 12) {
                    ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                        LanguageOptionCard(
                            language: language,
                            selected: coordinator.language == language
                        ) {
                            coordinator.select(language: language)
                        }
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }

    /// Said only in Chinese, because it is only true there: the interface is Chinese
    /// and the buttons still write Japanese (§17). Saying it in Japanese or English
    /// would be describing a choice the reader did not make.
    private var languageNote: String {
        tr(
            "ボタンは、選んだ言語に合わせて用意します。",
            "Your buttons will be set up for writing in English.",
            "界面为中文，按钮仍然用于书写日语。这是为在日本工作的中文使用者准备的。"
        )
    }
}

private struct LanguageOptionCard: View {
    let language: AppLanguage
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.endonym)
                        .font(Tokens.Font.body(15, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(caption)
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .strokeBorder(
                            selected ? Tokens.Window.accent : Tokens.Window.controlOff,
                            lineWidth: 1.5
                        )
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle().fill(Tokens.Window.accent).frame(width: 10, height: 10)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering && !selected ? Tokens.Window.surface : Tokens.Window.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? Tokens.Window.accent : Tokens.Window.hairline,
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
    }

    /// Written in the language of the row, not of the interface — the row is how a
    /// reader who cannot read the current interface finds their way out of it.
    private var caption: String {
        switch language {
        case .japanese: return "日本語で表示し、日本語の文章を書きます"
        case .english: return "English interface, English writing buttons"
        case .simplifiedChinese: return "中文界面，按钮书写日语"
        }
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
                    eyebrow: tr("ボタンを選ぶ", "Pick your buttons", "选择按钮"),
                    title: tr("主にどこで使いますか？", "Where will you use it most?", "主要在哪里使用？"),
                    subtitle: tr(
                        "用途に合う4つを用意します。次の画面で名前も指示も変更できます。",
                        "We'll set up four buttons for that. You can rename and reword them next.",
                        "将为你准备合适的4个按钮。名称和指令都可在下一步修改。"
                    )
                )

                HStack(alignment: .top, spacing: 10) {
                    Icon(.info, size: 14)
                        .foregroundStyle(Tokens.Window.accentText)
                        .opticalCentre()
                    Text(tr(
                        "ここで選ぶのは出発点です。名前、順番、AIへの指示は次の画面で自由に調整できます。",
                        "This is only a starting point. Names, order and the instruction behind each button are all editable on the next page.",
                        "这只是起点。名称、顺序和给AI的指令都可以在下一步自由调整。"
                    ))
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
                                    title: tr("現在のボタンを使う", "Keep my current buttons", "使用现有按钮"),
                                    caption: tr(
                                        "iPhoneと同期している設定をそのまま確認",
                                        "Review the set already synced from your iPhone",
                                        "查看已与 iPhone 同步的设置"
                                    ),
                                    titles: model.prompts.prefix(4).map(\.title),
                                    selected: coordinator.usesCurrentButtons
                                ) {
                                    coordinator.selectCurrentButtons()
                                }
                            }

                            ForEach(OnboardingPresetPack.available(for: coordinator.language), id: \.rawValue) { pack in
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
                        eyebrow: tr("ボタンを確認", "Review", "确认按钮"),
                        title: tr("使うボタンを確認", "Check your buttons", "确认要使用的按钮"),
                        subtitle: tr(
                            "先頭がメインボタンです。名前、指示、順番はここで変更できます。",
                            "The first row is your main button. Rename, reword and reorder them here.",
                            "第一行是主按钮。可在此修改名称、指令和顺序。"
                        )
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
                        ActionButton(tr("ボタンを追加", "Add a button", "添加按钮"), icon: .add, style: .secondary) {
                            coordinator.addDraft()
                        }
                    }
                }
                .frame(width: 540, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 16) {
                PillCaption(prefix: tr("", "Preview of ", ""), suffix: tr("のプレビュー", "", "的预览"))

                OnboardingBarPreview(titles: coordinator.buttonDrafts.map(\.title))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(tr(
                    "一番上のボタンは、iPhoneでもメインとして表示されます。",
                    "The top button is also the main one on your iPhone.",
                    "最上面的按钮在 iPhone 上也会显示为主按钮。"
                ))
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
                    IconButton(icon: .arrowUp, help: tr("上へ", "Move up", "上移"), enabled: index > 0) { onMove(-1) }
                    IconButton(icon: .arrowDown, help: tr("下へ", "Move down", "下移"), enabled: index < count - 1) { onMove(1) }
                }
                .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(draft.title.isEmpty ? tr("名称未設定", "Untitled", "未命名") : draft.title)
                            .font(Tokens.Font.body(14, weight: .medium))
                            .foregroundStyle(Tokens.Window.textPrimary)
                        if index == 0 { Badge(tr("メイン", "Main", "主要")) }
                    }
                    Text(draft.prompt.isEmpty ? tr("指示を入力してください", "Write an instruction", "请输入指令") : draft.prompt)
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 10)
                IconButton(icon: .edit, help: tr("編集", "Edit", "编辑")) { onToggleEdit() }
                IconButton(icon: .trash, help: tr("削除", "Delete", "删除"), enabled: count > 1) { onDelete() }
            }
            .padding(.horizontal, 14)
            .frame(height: height)

            if isEditing {
                Hairline()
                VStack(alignment: .leading, spacing: 10) {
                    SectionCaption(text: tr("ボタン名", "Button name", "按钮名称"))
                    SettingsField(
                        placeholder: tr("ボタン名", "Button name", "按钮名称"),
                        text: Binding(
                            get: { draft.title },
                            set: { value in
                                var next = draft
                                next.title = String(value.prefix(12))
                                onChange(next)
                            }
                        )
                    )

                    SectionCaption(text: tr("AIへの指示", "Instruction for the AI", "给AI的指令"))
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
            OnboardingMailScene(labels: titles.map { $0.isEmpty ? tr("未設定", "Untitled", "未设置") : $0 }) {
                OnboardingStaticMailBody(text: tr("明日の会議を15時に変更していただけますか。", "Could we move tomorrow's meeting to 3pm?", "明日の会議を15時に変更していただけますか。"))
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
                    eyebrow: tr("必要な設定", "One permission", "必要的设置"),
                    title: tr(
                        "文章を読み、同じ場所へ戻すために",
                        "To read your text and write it back",
                        "为了读取文字并写回原处"
                    ),
                    subtitle: tr(
                        "アクセシビリティは、いま選ばれている入力欄だけを読み書きするために必要です。マイクと画面収録は使いません。",
                        "Accessibility lets the app read and replace the field you are editing, and nothing else. No microphone, no screen recording.",
                        "辅助功能权限仅用于读写当前选中的输入框。不使用麦克风和录屏。"
                    )
                )

                Card(padding: 18) {
                    HStack(spacing: 14) {
                        IconPlate(icon: .accessibility, diameter: 42)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("アクセシビリティ", "Accessibility", "辅助功能"))
                                .font(Tokens.Font.body(14, weight: .medium))
                                .foregroundStyle(Tokens.Window.textPrimary)
                            Text(model.isTrusted
                                ? tr("許可済みです", "Granted", "已授权")
                                : tr(
                                    "システム設定で敬語ボタンを許可してください",
                                    "Turn KeigoButton on in System Settings",
                                    "请在系统设置中允许敬語ボタン"
                                ))
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
                    TeachingPillRow(number: "01", prefix: tr("", "Hover ", ""), suffix: tr("にカーソルを合わせて開く", " to open it", "，光标悬停即可展开"))
                    TeachingRow(number: "02", text: tr("ラベルを押して書き換える", "Press a button to rewrite", "点击标签进行改写"))
                    TeachingRow(number: "03", text: tr("結果を確認して置き換え", "Check the result and insert it", "确认结果后替换"))
                    TeachingRow(number: "04", text: tr("自由な指示をその場で入力", "Or type a one-off instruction", "也可现场输入自由指令"))
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
                    pendingText: tr("結果が出たら書き換える", "Insert when the result appears", "结果出来后进行改写"),
                    completedText: tr("書き戻し完了", "Written back", "已写回")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingMailScene(labels: [], showsBar: false) {
                    OnboardingPracticeEditor(
                        text: $sample,
                        isFocused: $focused,
                        fontSize: 15,
                        accessibilityLabel: tr("練習用メッセージ", "Practice message", "练习用消息")
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
    private static var sourceDraft: String {
        tr(
            "明日の15時の打ち合わせですが、資料の準備が間に合わないので、来週火曜日の同じ時間に変更したいです。",
            "About tomorrow's 3pm meeting — the materials won't be ready, so I'd like to move it to the same time next Tuesday.",
            "明日の15時の打ち合わせですが、資料の準備が間に合わないので、来週火曜日の同じ時間に変更したいです。"
        )
    }
    private static var suggestedGuidance: String {
        tr(
            "取引先向けに、簡潔なメールにしてください。",
            "Make it a short client email that opens with an apology.",
            "写成给客户的简洁邮件，开头先致歉。"
        )
    }

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
                        completedText: tr("カスタム指示で書き戻しました", "Written back with your instruction", "已使用自定义指令写回")
                    )
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(tr("入力例", "Example", "输入示例"))
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
                        accessibilityLabel: tr("カスタム練習用メッセージ", "Custom practice message", "自定义练习用消息")
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
    private static var sourceMessage: String {
        tr(
            "明日の15時からのプロジェクト定例、参加できそうですか？",
            "Can you make the project sync tomorrow at 3pm?",
            "明日の15時からのプロジェクト定例、参加できそうですか？"
        )
    }

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
                    pendingText: tr(
                        "例：参加できると丁寧に",
                        "e.g. yes, politely",
                        "例：礼貌地回答可以参加"
                    ),
                    completedText: tr("返信を書き戻しました", "Reply written back", "已写回回复")
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
                        placeholder: tr("# product への返信", "Reply in #product", "回复 #product"),
                        accessibilityLabel: tr("返信練習用メッセージ", "Reply practice message", "回复练习用消息")
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
                    eyebrow: tr("最後にひとつ", "One last thing", "最后一个问题"),
                    title: tr(
                        "敬語ボタンをどこで知りましたか？",
                        "Where did you hear about KeigoButton?",
                        "你是从哪里知道敬語ボタン的？"
                    ),
                    subtitle: tr(
                        "どこで見つけてもらえたのかを知るためだけの質問です。近いものを1つ選んでください。",
                        "Asked only so we know where people find us. Pick the closest one.",
                        "只是想知道大家从哪里找到我们。请选择最接近的一项。"
                    )
                )

                HStack(alignment: .top, spacing: 10) {
                    Icon(.info, size: 14)
                        .foregroundStyle(Tokens.Window.accentText)
                        .opticalCentre()
                    Text(tr(
                        "送るのは選んだ項目だけです。答えずに進んでも、機能は何も変わりません。",
                        "Only the option you pick is sent. Skipping changes nothing about the app.",
                        "只会发送你选择的选项。跳过不会影响任何功能。"
                    ))
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

/// The one page in first run that asks for money.
///
/// Composition is `SourceStep`'s — question left, stage right — rather than a layout
/// of its own, because a page that suddenly looks like an advertisement inside a setup
/// flow reads as an interruption by something other than the app.
///
/// **What is deliberately absent.** No countdown ticking by the second, no crossed-out
/// price animating, no 「今だけ」 without a date behind it. The deadline is real, it is
/// enforced by `desktop-checkout` against `desktop.welcome_offers.expires_at`, and a
/// deliberately unenforced one would be a 景表法 有利誤認 claim rather than a design
/// choice. What each card *must* carry is 特商法第12条の6's ①分量 and ②対価: the amount,
/// that it covers the first period only, the price it renews at afterwards, and that
/// it renews automatically.
private struct OfferStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var model: MainModel

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        self.model = coordinator.mainModel
    }

    private var currency: BillingCurrency { model.billingCurrency }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 22) {
                StepHeading(
                    eyebrow: remainingText.map {
                        tr("はじめての方限定 · \($0)", "New customers · \($0)", "新用户限定 · \($0)")
                    } ?? tr("はじめての方限定", "New customers", "新用户限定"),
                    title: tr(
                        "最初だけ、割引価格で Pro を試せます",
                        "Try Pro at a lower price, once",
                        "首次可以优惠价体验 Pro"
                    ),
                    subtitle: tr(
                        "無料のままでも月50回まで書き換えできます。Pro は月1,000回まで。この価格は今回の設定から\(PlanPricing.welcomeOfferWindowHours)時間だけです。",
                        "The free plan keeps its 50 rewrites a month. Pro raises that to 1,000. This price is available for \(PlanPricing.welcomeOfferWindowHours) hours from now.",
                        "免费版每月仍可改写50次，Pro 可达1,000次。此价格仅在设置后的\(PlanPricing.welcomeOfferWindowHours)小时内有效。"
                    )
                )

                HStack(alignment: .top, spacing: 10) {
                    Icon(.info, size: 14)
                        .foregroundStyle(Tokens.Window.accentText)
                        .opticalCentre()
                    Text(tr(
                        "あとで決めても大丈夫です。この価格はホーム画面からも受け取れます。",
                        "Deciding later is fine — the same price is waiting on the home screen.",
                        "稍后再决定也可以，主页同样可以使用这个价格。"
                    ))
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 300, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            OnboardingVisualStage {
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    OfferCard(
                        interval: .year,
                        currency: currency,
                        selected: coordinator.offerInterval == .year
                    ) { coordinator.select(offerInterval: .year) }
                    OfferCard(
                        interval: .month,
                        currency: currency,
                        selected: coordinator.offerInterval == .month
                    ) { coordinator.select(offerInterval: .month) }

                    // The honest replacement for 「税込」 — the same sentence the plan
                    // pane carries, and for the same reason (`docs/billing.md` §10).
                    Text(tr(
                        "表示価格が実際にご請求される金額です。いつでもワンクリックで解約できます。",
                        "The price shown is the amount you are charged. Cancel any time, in one click.",
                        "所示价格即为实际收费金额。可随时一键取消。"
                    ))
                        .font(Tokens.Font.body(11))
                        .foregroundStyle(Tokens.Window.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
            }
            .padding(.vertical, OnboardingMetrics.visualVerticalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }

    private var remainingText: String? {
        coordinator.offerExpiresAt.flatMap { PlanPricing.offerRemainingText(until: $0) }
    }
}

private struct OfferCard: View {
    let interval: Entitlement.Interval
    let currency: BillingCurrency
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var offer: PlanPricing.Amount { PlanPricing.welcomeOffer(interval, in: currency) }
    private var list: PlanPricing.Amount { PlanPricing.list(interval, in: currency) }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(interval == .year
                         ? tr("年払い", "Yearly", "年付")
                         : tr("月払い", "Monthly", "月付"))
                        .font(Tokens.Font.body(13, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    if interval == .year {
                        let months = PlanPricing.monthsFree(in: currency)
                        Text(tr("\(months)ヶ月分お得", "\(months) months free", "省\(months)个月"))
                            .font(Tokens.Font.body(11, weight: .medium))
                            .foregroundStyle(Tokens.Window.accentText)
                    }
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

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(offer.display)
                        .font(Tokens.Font.display(22))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(unit)
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textSecondary)
                    // The list price beside it, struck through. 二重価格表示 is only
                    // defensible when the "before" price is one actually being charged
                    // — ¥1,480 / ¥14,400 are the live catalog, and they are what this
                    // same account pays from the second period onward.
                    Text(list.display)
                        .font(Tokens.Font.body(12))
                        .strikethrough()
                        .foregroundStyle(Tokens.Window.textTertiary)
                }

                Text(renewal)
                    .font(Tokens.Font.body(11))
                    .foregroundStyle(Tokens.Window.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering && !selected ? Tokens.Window.surface : Tokens.Window.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? Tokens.Window.accent : Tokens.Window.hairline,
                        lineWidth: selected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
    }

    private var unit: String {
        let months = PlanPricing.welcomeOfferMonthlyPeriods
        return interval == .year
            ? tr("/ 初年度", "for the first year", "首年")
            : tr("/ 月（最初の\(months)ヶ月）", "/ month for \(months) months", "/ 月（前\(months)个月）")
    }

    /// 特商法第12条の6 ②対価. A discounted first period is only half the price; the other
    /// half is what it becomes, and the article is why that sentence is on the card
    /// rather than at the card.
    private var renewal: String {
        let months = PlanPricing.welcomeOfferMonthlyPeriods
        return interval == .year
            ? tr(
                "2年目以降は年 \(list.display) を自動更新",
                "Then \(list.display) a year, renews automatically",
                "第二年起每年 \(list.display)，自动续订"
            )
            : tr(
                "\(months)ヶ月後は月 \(list.display) を自動更新",
                "After \(months) months, \(list.display) a month, renews automatically",
                "\(months)个月后每月 \(list.display)，自动续订"
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
                    CompletionRow(text: tr("アカウントとボタンを同期", "Account and buttons synced", "账户与按钮已同步"))
                    CompletionRow(text: tr("アクセシビリティを許可", "Accessibility granted", "已授予辅助功能权限"))
                    CompletionRow(text: tr("書き換えの操作を確認", "Rewriting learned", "已了解改写操作"))
                    CompletionRow(text: tr("一度だけのカスタム指示を確認", "One-off instructions learned", "已了解一次性自定义指令"))
                    CompletionRow(text: tr("コピーから返信する操作を確認", "Replying from a copy learned", "已了解从复制内容回复"))
                }
            }
            .frame(width: 380, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            OnboardingVisualStage {
                OnboardingMailScene(labels: coordinator.mainModel.prompts.enabledForHoverRow.map(\.title)) {
                    OnboardingStaticMailBody(
                        text: tr(
                            "恐れ入りますが、明日の会議を15時に変更していただけますでしょうか。",
                            "Would it be possible to move tomorrow's meeting to 3pm?",
                            "恐れ入りますが、明日の会議を15時に変更していただけますでしょうか。"
                        ),
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
    var prefix: String = ""
    let suffix: String

    var body: some View {
        PillSentence(before: prefix, after: suffix, scale: 0.52, spacing: 6)
            .font(Tokens.Font.body(12, weight: .medium))
            .foregroundStyle(Tokens.Window.textTertiary)
    }
}

/// A sentence with the real bar drawn inside it.
///
/// Japanese puts the pill mid-sentence and English almost never can — 「バーのプレビュー」
/// is "Preview of ⟨bar⟩" — so both sides are translatable and either may be empty. An
/// empty side is **omitted**, not laid out: an empty `Text` still takes the HStack's
/// spacing, which leaves a gap beside the pill that nothing in the copy explains.
private struct PillSentence: View {
    let before: String
    let after: String
    var scale: CGFloat = 0.58
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            if !before.isEmpty { Text(before) }
            PillPreview(scale: scale)
            if !after.isEmpty { Text(after) }
        }
    }
}

private struct PillStepHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("いつもの使い方", "How you'll use it", "日常用法"))
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            PillSentence(
                before: tr("画面下の", "", "画面下方的"),
                after: tr("が待っています", " lives at the bottom.", "在等着你"),
                scale: 0.72,
                spacing: 8
            )
            .font(Tokens.Font.display(20))
            .tracking(Tokens.Font.displayTracking(20))
            .foregroundStyle(Tokens.Window.textPrimary)
            .lineLimit(1)
            PillSentence(
                before: tr("入力欄に文章を置いたまま、", "Leave the field focused and hover ", "让文字留在输入框中，将光标移到"),
                after: tr("へカーソルを移動。", ".", "上。")
            )
            .font(Tokens.Font.body(14))
            .foregroundStyle(Tokens.Window.textSecondary)
            Text(tr("入力欄のフォーカスは失われません。", "The field never loses focus.", "输入框不会失去焦点。"))
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textSecondary)
        }
    }
}

private struct PracticeStepHeading: View {
    let completed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("実際に試す", "Try it", "实际试用"))
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(completed
                ? tr("書き戻せました", "It went back in", "已写回")
                : tr("選んだボタンで試してみましょう", "Try one of your buttons", "用选好的按钮试试看"))
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            if completed {
                Text(tr(
                    "いまの操作が、ほかのアプリでも同じように使えます。",
                    "That same move works in every other app.",
                    "同样的操作在其他应用中也能使用。"
                ))
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
            } else {
                PillSentence(
                    before: tr("本文にフォーカスを残し、", "Leave the body focused, open ", "保持正文处于焦点状态，展开"),
                    after: tr("を開いて、好きなボタンを押します。", " and press any button.", "，然后点击任意按钮。")
                )
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
            Text(tr("返信を試す", "Try a reply", "试试回复"))
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(completed
                ? tr("返信を書き戻せました", "The reply went back in", "回复已写回")
                : tr("コピーしたメッセージに返信してみましょう", "Reply to the message you copied", "试着回复你复制的消息"))
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            if completed {
                Text(tr(
                    "コピーから返信まで、実際の操作で完了しました。",
                    "Copy to reply, done for real.",
                    "从复制到回复，已用真实操作完成。"
                ))
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
            } else {
                PillSentence(
                    before: tr(
                        "メッセージをコピーし、返信欄にフォーカスしたまま",
                        "Copy the message, focus the reply box, then open ",
                        "复制消息，将焦点留在回复框中，然后展开"
                    ),
                    after: tr("を開きます。", ".", "。")
                )
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
            Text(tr("カスタム指示を試す", "Try a one-off", "试试自定义指令"))
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(completed
                ? tr("一度だけの指示で書き戻せました", "Your one-off instruction went in", "已用一次性指令写回")
                : tr("このメールだけの仕上げ方を伝えましょう", "Say how this one email should land", "告诉它这封邮件该怎么写"))
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            if completed {
                Text(tr(
                    "保存済みのボタンを変えずに、その場だけの指示を使えます。",
                    "A one-off instruction, without touching your saved buttons.",
                    "无需修改已保存的按钮，也能使用一次性指令。"
                ))
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
            } else {
                PillSentence(
                    before: tr("本文にフォーカスを残し、", "Leave the body focused, open ", "保持正文处于焦点状态，展开"),
                    after: tr("を開いて右端の ✎ を押します。", " and press ✎ on the right.", "，然后点击最右侧的 ✎。")
                )
                .font(Tokens.Font.body(14))
                .foregroundStyle(Tokens.Window.textSecondary)
                Text(tr(
                    "✎ は、その書き換えに一度だけ使う指示を入力するボタンです。入力後に生成し、結果を入れ替えてください。",
                    "✎ takes an instruction used for this rewrite only. Type it, generate, then insert the result.",
                    "✎ 用于输入仅本次改写使用的指令。输入后生成，再替换结果。"
                ))
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
            Text(tr("セットアップ完了", "All set", "设置完成"))
                .font(Tokens.Font.body(12, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(tr("準備できました", "You're ready", "准备就绪"))
                .font(Tokens.Font.display(20))
                .tracking(Tokens.Font.displayTracking(20))
                .foregroundStyle(Tokens.Window.textPrimary)
            PillSentence(
                before: tr("文章にフォーカスを置き、画面下の", "Focus your text and open ", "让焦点停在文字上，展开画面下方的"),
                after: tr("を開くだけです。", " at the bottom. That's it.", "即可。")
            )
            .font(Tokens.Font.body(14))
            .foregroundStyle(Tokens.Window.textSecondary)
            Text(tr(
                "ウインドウを閉じても、敬語ボタンはメニューバーと画面下に残ります。",
                "Closing this window doesn't quit — KeigoButton stays in the menu bar and at the bottom of your screen.",
                "关闭窗口后，敬語ボタン仍会保留在菜单栏和画面下方。"
            ))
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
    var prefix: String = ""
    let suffix: String

    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(Tokens.Font.mono(12))
                .foregroundStyle(Tokens.Window.accentText)
                .frame(width: 22, alignment: .leading)
            PillSentence(before: prefix, after: suffix)
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
        return titles.isEmpty
            ? OnboardingPresetPack.starter.buttonTitles
            : titles
    }

    var body: some View {
        OnboardingVisualStage {
            OnboardingMailScene(labels: labels) {
                OnboardingStaticMailBody(text: tr(
                    "明日の会議、15時に変更しといて",
                    "move tomorrows meeting to 3, i cant make the morning",
                    "明日の会議、15時に変更しといて"
                ))
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
