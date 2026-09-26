import AppKit
import AVFoundation
import DesktopRewriteKit
import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var coordinator: OnboardingCoordinator
    var buttonExampleIndex = 0

    var body: some View {
        VStack(spacing: 16) {
            Group {
                switch coordinator.step {
                case .language: LanguageStep(coordinator: coordinator)
                case .welcome: WelcomeStep(coordinator: coordinator)
                case .name: NameStep(coordinator: coordinator)
                case .purpose, .writingStyle: ButtonPurposeStep(coordinator: coordinator, initialPreviewIndex: buttonExampleIndex)
                case .review: ButtonSetupReview(coordinator: coordinator)
                case .access: AccessStep(coordinator: coordinator)
                case .bar, .practice: PracticeStep(coordinator: coordinator)
                case .customPractice: CustomPracticeStep(coordinator: coordinator)
                case .replyPractice: ReplyPracticeStep(coordinator: coordinator)
                case .source: SourceStep(coordinator: coordinator)
                case .offer: OfferStep(coordinator: coordinator)
                case .complete: CompleteStep(coordinator: coordinator)
                }
            }
            .id(coordinator.step)
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: coordinator.step)
            OnboardingNavigationBar(coordinator: coordinator)
        }
        .padding(.horizontal, 32)
        .padding(.top, 48)
        .padding(.bottom, 24)
        .background(Tokens.Window.environment)
        .id(coordinator.language)
        .ignoresSafeArea()
        .environment(\.onboardingPresentation, true)
        .onExitCommand {
            if coordinator.step != .language { coordinator.back() }
        }
    }
}

private enum OnboardingMetrics {
    static let pagePadding: CGFloat = 0
    static let contentWidth: CGFloat = 1016
    static let contentTopPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 0
    static let navigationHeight: CGFloat = 58
    static let visualVerticalInset: CGFloat = 0
}

private struct OnboardingNavigationBar: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var model: MainModel

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        self.model = coordinator.mainModel
    }

    var body: some View {
        ZStack {
            if coordinator.step != .language {
                ProgressRail(step: coordinator.step)
                    .allowsHitTesting(false)
            }
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
                        primaryButton(tr("続ける", "Continue", "继续"))
                    }

                case .name:
                    primaryButton(
                        model.isSavingName
                            ? tr("名前を保存中…", "Saving your name…", "正在保存名字…")
                            : coordinator.isPreparingPurpose
                            ? tr("準備中…", "Preparing…", "准备中…")
                            : tr("続ける", "Continue", "继续"),
                        enabled: !coordinator.isPreparingPurpose && !model.isSavingName
                            && model.hasDisplayNameDraft
                    )

                case .purpose, .writingStyle:
                    primaryButton(tr("続ける", "Continue", "继续"), enabled: coordinator.canConfirmButtons)
                case .review:
                    primaryButton(tr("保存して続ける", "Save and continue", "保存并继续"), enabled: coordinator.canConfirmButtons && !coordinator.isSavingButtons)

                case .access:
                    if model.isTrusted {
                        primaryButton(tr("続ける", "Continue", "继续"))
                    } else {
                        ActionButton(
                            tr("システム設定を開く", "Open System Settings", "打开系统设置"),
                            style: .secondary
                        ) {
                            // Captured separately from the system dialog: this leg asks
                            // just as much and otherwise leaves no trace anywhere.
                            model.recordAccessibilityPrompt(
                                source: .onboarding,
                                method: .settingsLink
                            )
                            openAccessibilitySettings()
                        }
                        ActionButton(tr("許可する", "Grant access", "授予权限")) {
                            model.requestAccessibility(source: .onboarding)
                        }
                    }

                case .bar, .practice:
                    LinkButton(title: tr("あとで始める", "Skip for now", "稍后再说")) { coordinator.skipEducation() }
                    primaryButton(tr("カスタムも練習", "Try a custom one", "练习自定义指令"), enabled: coordinator.rewritePracticeCompleted)

                case .customPractice:
                    LinkButton(title: tr("あとで始める", "Skip for now", "稍后再说")) { coordinator.skipEducation() }
                    primaryButton(tr("返信も練習", "Try a reply", "练习回复"), enabled: coordinator.customPracticeCompleted)

                case .replyPractice:
                    LinkButton(title: tr("あとで始める", "Skip for now", "稍后再说")) { coordinator.skipEducation() }
                    primaryButton(tr("次へ", "Next", "下一步"), enabled: coordinator.replyPracticeCompleted)

                case .source:
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
            .name: tr("名前", "Name", "名字"),
            .writingStyle: tr("スタイル", "Style", "风格"),
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
        HStack(spacing: 6) {
            ForEach(Array(Self.steps.enumerated()), id: \.element) { index, _ in
                Capsule()
                    .fill(index == currentIndex ? Tokens.Window.textPrimary : Tokens.Window.textPrimary.opacity(index < currentIndex ? 0.22 : 0.08))
                    .frame(width: index == currentIndex ? 16 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("セットアップの進行状況", "Setup progress", "设置进度"))
        .accessibilityValue("\(currentIndex + 1) / \(Self.steps.count)")
    }
}

private struct WelcomeStep: View {
    @ObservedObject private var model: MainModel
    @State private var showsEmail = false
    #if DEBUG
    private var emailPreview: Bool { AsideDesignPreview.state == "signup" || AsideDesignPreview.state == "error" }
    #else
    private let emailPreview = false
    #endif

    // The coordinator is not held: everything this page reads and both errors it used
    // to print moved to 名前 with the field, and observing it would only redraw the
    // sign-in form for changes on another page.
    init(coordinator: OnboardingCoordinator) {
        self.model = coordinator.mainModel
    }

    var body: some View {
        OnboardingSplitPage {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 8) {
                    AppMark(size: 26)
                    Text(tr("敬語ボタン", "KeigoButton", "敬語ボタン"))
                        .font(Tokens.LightFont.body(18, weight: .medium))
                }
                Text(tr("書きたいことを、\nどこでも整える。", "Write anywhere.\nPolish it in place.", "想写的内容，\n随处都能整理好。"))
                    .font(Tokens.LightFont.body(40, weight: .medium))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tr("入力中の文章を、その場に合う言葉へ。", "The right words, right where you’re writing.", "把正在输入的文字，换成合适的表达。"))
                    .font(Tokens.LightFont.Onboarding.body)
                    .foregroundStyle(Tokens.Window.textSecondary)
                if model.isSignedIn { connectedContent } else { authenticationContent }
            }
            .foregroundStyle(Tokens.Window.textPrimary)
            .padding(.vertical, 16)
        } visual: {
            OnboardingVisualStage(artwork: .glow) {
                OnboardingMascotHero().frame(width: 344, height: 344)
            }
        }
    }

    private var connectedContent: some View {
        Card(padding: 20, radius: 16) {
            HStack(spacing: 12) {
                StatusDot(ok: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("アカウントに接続済み", "Connected to your account", "已连接账户"))
                        .font(Tokens.LightFont.body(18, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(model.signedInEmail ?? "")
                        .font(Tokens.LightFont.body(16))
                        .foregroundStyle(Tokens.Window.textPrimary)
                }
            }
        }
    }

    private var authenticationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            GoogleSignInButton(isLoading: model.isAuthenticating) {
                model.signInWithGoogle()
            }

            HStack(spacing: 12) {
                Hairline()
                Text(tr("または", "or", "或"))
                    .font(Tokens.LightFont.body(13))
                    .foregroundStyle(Tokens.Window.textTertiary)
                Hairline()
            }

            if showsEmail || emailPreview {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsField(placeholder: tr("メールアドレス", "Email address", "邮箱地址"), text: $model.email)
                    SettingsField(placeholder: tr("パスワード", "Password", "密码"), text: $model.password, secure: true)
                    if model.authMode == .signUp {
                        SettingsField(placeholder: tr("パスワード（確認）", "Confirm password", "确认密码"), text: $model.passwordConfirm, secure: true)
                    }

                    if let error = model.authError {
                        Text(error)
                            .font(Tokens.LightFont.Onboarding.body)
                            .foregroundStyle(Tokens.Window.error)
                    }
                    if let notice = model.authNotice {
                        Text(notice)
                            .font(Tokens.LightFont.body(16))
                            .foregroundStyle(Tokens.Window.textPrimary)
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
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) { showsEmail = true }
                } label: {
                    Text(tr("メールアドレスで続ける", "Continue with email", "使用邮箱继续"))
                        .font(Tokens.LightFont.Onboarding.action)
                        .foregroundStyle(Tokens.Window.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.Window.secondaryPanel))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.Window.hairline))
                }
                .buttonStyle(LightPressStyle())
                .cursor(.pointingHand)
            }
        }
        .padding(20)
        .background(Tokens.Window.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Tokens.Window.hairline))
    }

    private var canSubmit: Bool {
        !model.isAuthenticating && model.email.contains("@") && model.password.count >= 6
    }
}

/// The name, and nothing else.
///
/// It was a second card on アカウント until 2026-08-23, stacked under the sign-in it
/// shared the page with, where it read as one more field of the signup form — something
/// to fill in because a form was asking. It is a hard gate (§15) whose answer signs
/// every reply the app writes, and that is not a thing to explain in a caption beside a
/// password box.
///
/// One field, and **no Save button beside it**: Continue saves the draft, so a second
/// action on the same value would be the dead competing action §15 keeps off these
/// pages. ⏎ in the field is the same action as Continue, for the same reason.
///
/// The stage answers "what is this for?" without a sentence: the name appears in a
/// reply as it is typed, in the place the app would actually put it.
private struct NameStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var model: MainModel

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        self.model = coordinator.mainModel
    }

    var body: some View {
        OnboardingSplitPage {
            VStack(alignment: .leading, spacing: 20) {
                StepHeading(
                    eyebrow: tr("あなたのこと", "About you", "关于你"),
                    // Short enough to hold one line at 20 pt in a 320 pt column: the
                    // longer 「返信では、どの名前で名乗りますか？」 wrapped mid-verb, and
                    // Japanese has no word boundary to break at.
                    title: tr(
                        "返信で名乗る名前は？",
                        "What name should your replies use?",
                        "回复时用哪个名字自称？"
                    ),
                    subtitle: tr(
                        "普段、相手に名乗る名前です。あとから設定でいつでも変更できます。",
                        "The name other people know you by. You can change it any time in Settings.",
                        "他人熟悉的称呼。之后可随时在设置中更改。"
                    )
                )

                SettingsField(
                    // Each language's own filler name, not a translation of one person:
                    // 山田太郎, John Smith and 张三 are what a form example looks like to
                    // a reader of that language. 山田树 was the Japanese example
                    // transliterated, which is a name no Chinese speaker would recognise
                    // as a placeholder.
                    placeholder: tr("例：山田 太郎", "e.g. John Smith", "例如：张三"),
                    text: $model.displayNameDraft,
                    autofocus: true,
                    onSubmit: { coordinator.advance() }
                )
                .frame(maxWidth: .infinity)

                HStack(alignment: .top, spacing: 10) {
                    Icon(.info, size: 14)
                        .foregroundStyle(Tokens.Window.accentText)
                        .opticalCentre()
                    Text(tr(
                        "メールでは署名に、返信ではあなた宛の呼びかけを見分けるために使います。",
                        "It signs your emails, and it is how a reply can tell a message was addressed to you.",
                        "用于邮件署名，也用来识别消息是否在称呼你。"
                    ))
                        .font(Tokens.LightFont.body(16))
                        .foregroundStyle(Tokens.Window.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Both failures belong to Continue — one saving the name, one loading
                // the account's buttons — so both are read on the page that presses it.
                if let error = model.profileError ?? coordinator.purposeError {
                    Text(error)
                        .font(Tokens.LightFont.body(16))
                        .foregroundStyle(Tokens.Window.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        } visual: {
            NameIllustration(name: model.displayNameDraft)
        }
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
        OnboardingChoicePage(width: 480) {
            VStack(spacing: 8) {
                Image("MascotPortrait")
                    .resizable().interpolation(.high).scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
                StepHeading(eyebrow: "", title: tr("使う言語を選んでください", "Choose your language", "请选择使用的语言"),
                    subtitle: tr("アプリの表示言語です。あとから変更できます。", "Choose the language you’d like to use. You can change it later.", "选择应用的显示语言。之后可随时更改。"), centered: true, titleWeight: .semibold)
            }
            VStack(spacing: 0) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.rawValue) { index, language in
                    if index > 0 { Color.clear.frame(height: 4) }
                    LanguageOptionCard(language: language, selected: coordinator.language == language) {
                        coordinator.select(language: language)
                    }
                }
            }
            .padding(6)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tokens.Window.hairline))
            Text(languageNote)
                .font(Tokens.LightFont.Onboarding.caption)
                .foregroundStyle(Tokens.Window.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Said only in Chinese, because it is only true there: the interface is Chinese
    /// and the buttons still write Japanese (§17). Saying it in Japanese or English
    /// would be describing a choice the reader did not make.
    private var languageNote: String {
        tr(
            "新しい文章は選んだ言語で。書き換えは元の言語を保ちます。",
            "New messages use English. Polishing keeps the language of your draft.",
            "界面为中文，新文章默认使用日语。润色时保留原文语言。"
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
            HStack(alignment: .center, spacing: 16) {
                Text(language == .japanese ? "あ" : language == .english ? "A" : "文")
                    .font(Tokens.LightFont.body(22, weight: .medium))
                    .foregroundStyle(selected ? Tokens.Window.accentText : Tokens.Window.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(Tokens.Window.surface, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(language.endonym)
                        .font(Tokens.LightFont.body(18, weight: .semibold))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(caption)
                        .font(Tokens.LightFont.Onboarding.caption)
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .strokeBorder(
                            selected ? Tokens.Window.accentText : Tokens.Window.textTertiary,
                            lineWidth: 1
                        )
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle().fill(Tokens.Window.accentText).frame(width: 10, height: 10)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Tokens.Window.accentTint : hovering ? Tokens.Window.surfaceHover : .clear)
            )

        }
        .buttonStyle(LightPressStyle())
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Written in the language of the row, not of the interface — the row is how a
    /// reader who cannot read the current interface finds their way out of it.
    private var caption: String {
        switch language {
        case .japanese: return "日本語で表示し、日本語の文章を書きます"
        case .english: return "English interface and new messages"
        case .simplifiedChinese: return "中文界面，按钮书写日语"
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
        OnboardingSplitPage {
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
                                .font(Tokens.LightFont.body(18, weight: .medium))
                                .foregroundStyle(Tokens.Window.textPrimary)
                            Text(model.isTrusted
                                ? tr("許可済みです", "Granted", "已授权")
                                : tr(
                                    "システム設定で敬語ボタンを許可してください",
                                    "Turn KeigoButton on in System Settings",
                                    "请在系统设置中允许敬語ボタン"
                                ))
                                .font(Tokens.LightFont.body(16))
                                .foregroundStyle(Tokens.Window.textPrimary)
                        }
                        Spacer()
                        StatusDot(ok: model.isTrusted)
                    }
                }

            }

        } visual: {
            PermissionIllustration(granted: model.isTrusted)
        }
    }

}

private struct PracticeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    var body: some View {
        GuidedPracticePage(coordinator: coordinator, kind: .rewrite, initialText: coordinator.tutorialSample)
    }
}

private struct CustomPracticeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    var body: some View {
        GuidedPracticePage(coordinator: coordinator, kind: .custom, initialText: tr(
            "明日の15時の打ち合わせですが、資料の準備が間に合わないので、来週火曜日の同じ時間に変更したいです。",
            "About tomorrow's 3pm meeting — the materials won't be ready, so I'd like to move it to the same time next Tuesday.",
            "明日の15時の打ち合わせですが、資料の準備が間に合わないので、来週火曜日の同じ時間に変更したいです。"))
    }
}

private struct ReplyPracticeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    var body: some View {
        GuidedPracticePage(coordinator: coordinator, kind: .reply, initialText: "")
    }
}

private struct GuidedPracticePage: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    let kind: OnboardingLesson.Kind
    let initialText: String
    @State private var text: String
    @State private var focusRequest: UUID?
    @State private var selectedSource = false

    init(coordinator: OnboardingCoordinator, kind: OnboardingLesson.Kind, initialText: String) {
        self.coordinator = coordinator
        self.kind = kind
        self.initialText = initialText
        _text = State(initialValue: initialText)
        _focusRequest = State(initialValue: kind == .reply ? nil : UUID())
    }

    private var source: String {
        tr("明日の15時からのプロジェクト定例、参加できそうですか？",
           "Can you make the project sync tomorrow at 3pm?",
           "明日の15時からのプロジェクト定例、参加できそうですか？")
    }

    var body: some View {
        VStack(spacing: 16) {
            if let lesson = coordinator.lesson {
                LessonHeading(lesson: lesson, copyOnly: coordinator.lessonCopyOnly)
                OnboardingVisualStage {
                    if kind == .reply {
                        OnboardingSlackScene(message: source, copied: selectedSource, onCopy: {
                            coordinator.copyReplyPracticeMessage(source)
                            selectedSource = true
                            focusRequest = UUID()
                        }) {
                            editor(sessionID: lesson.id)
                        }
                    } else {
                        OnboardingMailScene(labels: [], showsBar: false) {
                            VStack(spacing: 0) {
                                if lesson.phase == .restore {
                                    ActionButton(tr("文章を戻す", "Restore sample", "恢复示例")) {
                                        text = initialText
                                        focusRequest = UUID()
                                    }
                                    .padding(12)
                                }
                                editor(sessionID: lesson.id)
                            }
                        }
                    }
                }
                .padding(.bottom, OnboardingMetrics.visualVerticalInset)
            }
        }
        .frame(maxWidth: OnboardingMetrics.contentWidth, maxHeight: .infinity)
        .padding(.horizontal, OnboardingMetrics.pagePadding)
        .padding(.top, OnboardingMetrics.contentTopPadding)
        .padding(.bottom, OnboardingMetrics.bottomPadding)
    }

    private func editor(sessionID: UUID) -> some View {
        OnboardingPracticeEditor(text: $text, focusRequest: focusRequest, fontSize: 18,
            accessibilityLabel: tr("練習用メッセージ", "Practice message", "练习消息"),
            onStatus: { ready, empty in
                coordinator.overlay.lessonEvent(.editor(ready: ready, empty: empty), sessionID: sessionID)
            })
            .background(.white)
    }
}

private struct OnboardingPracticeEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: UUID?
    var fontSize: CGFloat
    var contentInset = NSSize(width: 14, height: 16)
    var placeholder: String?
    let accessibilityLabel: String
    let onStatus: (Bool, Bool) -> Void

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
        textView.textColor = NSColor(Tokens.Window.textPrimary)
        textView.insertionPointColor = NSColor(Tokens.Window.accentText)
        textView.string = text
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.statusChanged = { [weak coordinator = context.coordinator] in coordinator?.report() }
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.requestFocus(focusRequest)
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
        context.coordinator.requestFocus(focusRequest)
        context.coordinator.report()
        textView.needsDisplay = true
    }

    private var editorFont: NSFont {
        .systemFont(ofSize: fontSize)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: OnboardingPracticeEditor
        weak var textView: NSTextView?
        private var lastFocusRequest: UUID?
        private var appliedFocusRequest: UUID?

        init(_ parent: OnboardingPracticeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            report()
        }

        func requestFocus(_ request: UUID?) {
            guard let request, request != lastFocusRequest else { return }
            lastFocusRequest = request
            report()
        }

        func report() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView else { return }
                if let request = self.lastFocusRequest, request != self.appliedFocusRequest,
                   let window = textView.window, window.isKeyWindow,
                   window.makeFirstResponder(textView) {
                    self.appliedFocusRequest = request
                }
                let ready = textView.window?.isKeyWindow == true && textView.window?.firstResponder === textView
                self.parent.onStatus(ready, textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    final class PracticeNSTextView: NSTextView {
        var placeholder: String?
        var statusChanged: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
            if let window {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(windowFocusChanged), name: name, object: window)
                }
            }
            statusChanged?()
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            statusChanged?()
            return accepted
        }

        override func resignFirstResponder() -> Bool {
            let accepted = super.resignFirstResponder()
            statusChanged?()
            return accepted
        }

        @objc private func windowFocusChanged(_ notification: Notification) { statusChanged?() }


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
/// dot. It carried 「答えない」 beside the forward action until 2026-08-21, and the answer
/// rate was 1 in 3 — so the link is gone and 次へ waits for a choice. Forcing an answer
/// is only honest because 「その他」 is one of the eight: nobody has to invent a channel
/// they did not come from.
private struct SourceStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        OnboardingChoicePage(width: 640) {
            StepHeading(eyebrow: "", title: tr("敬語ボタンをどこで知りましたか？", "Where did you hear about KeigoButton?", "你是从哪里知道敬語ボタン的？"),
                subtitle: tr("近いものを1つ選んでください。送るのは選んだ項目だけです。", "Pick the closest one. Only your selection is sent.", "请选择最接近的一项。只会发送你的选项。"), centered: true)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(OnboardingSource.allCases, id: \.self) { source in
                    SourceOptionCard(source: source, selected: coordinator.selectedSource == source) {
                        coordinator.select(source: source)
                    }
                }
            }
            .padding(8)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
        }
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
                    .font(Tokens.LightFont.body(16, weight: .medium))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                ZStack {
                    Circle()
                        .strokeBorder(selected ? Tokens.Window.accentText : Tokens.Window.textTertiary, lineWidth: 1)
                        .frame(width: 18, height: 18)
                    if selected {
                        Circle().fill(Tokens.Window.accentText).frame(width: 10, height: 10)
                    }
                }
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering && !selected ? Tokens.Window.surface : Tokens.Window.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Tokens.Window.accentText : Tokens.Window.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(LightPressStyle())
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
        OnboardingChoicePage(width: 560) {
            StepHeading(eyebrow: remainingText ?? "", title: tr("Pro を、はじめやすく。", "A little more room to write.", "轻松开始使用 Pro。"),
                subtitle: tr("無料プランは月\(PlanPricing.freeMonthlyRewrites)回。Pro は月\(PlanPricing.proMonthlyRewritesDisplay)回まで。", "Keep \(PlanPricing.freeMonthlyRewrites) rewrites a month free, or get up to \(PlanPricing.proMonthlyRewritesDisplay) with Pro.", "免费版每月\(PlanPricing.freeMonthlyRewrites)次，Pro 每月最高\(PlanPricing.proMonthlyRewritesDisplay)次。"), centered: true)
            VStack(spacing: 0) {
                OfferCard(interval: .year, currency: currency, selected: coordinator.offerInterval == .year) {
                    coordinator.select(offerInterval: .year)
                }
                Hairline().padding(.horizontal, 16)
                OfferCard(interval: .month, currency: currency, selected: coordinator.offerInterval == .month) {
                    coordinator.select(offerInterval: .month)
                }
            }
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            Text(tr("表示価格が実際の請求額です。いつでも解約できます。あとでホーム画面からも選べます。", "The price shown is what you pay. Cancel any time. You can also decide later from Home.", "所示价格即为实际收费金额，可随时取消。也可稍后在主页选择。"))
                .font(Tokens.LightFont.Onboarding.caption)
                .foregroundStyle(Tokens.Window.textSecondary)
                .multilineTextAlignment(.center)
        }
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
                        .font(Tokens.LightFont.body(16, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    if interval == .year {
                        let months = PlanPricing.monthsFree(in: currency)
                        Text(tr("\(months)ヶ月分お得", "\(months) months free", "省\(months)个月"))
                            .font(Tokens.LightFont.body(13, weight: .medium))
                            .foregroundStyle(Tokens.Window.accentText)
                    }
                    Spacer(minLength: 6)
                    ZStack {
                        Circle()
                            .strokeBorder(selected ? Tokens.Window.accentText : Tokens.Window.textTertiary, lineWidth: 1)
                            .frame(width: 18, height: 18)
                        if selected {
                            Circle().fill(Tokens.Window.accentText).frame(width: 10, height: 10)
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(offer.display)
                        .font(Tokens.LightFont.display(22))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(unit)
                        .font(Tokens.LightFont.body(13))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    // The list price beside it, struck through. 二重価格表示 is only
                    // defensible when the "before" price is one actually being charged
                    // — ¥1,480 / ¥14,400 are the live catalog, and they are what this
                    // same account pays from the second period onward.
                    Text(list.display)
                        .font(Tokens.LightFont.body(13))
                        .strikethrough()
                        .foregroundStyle(Tokens.Window.textTertiary)
                }

                Text(renewal)
                    .font(Tokens.LightFont.body(13))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(hovering && !selected ? Tokens.Window.surfaceHover : .clear)
            )

        }
        .buttonStyle(LightPressStyle())
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        OnboardingSplitPage {
            VStack(alignment: .leading, spacing: 24) {
                AppMark(size: 40)
                StepHeading(eyebrow: "", title: tr("準備ができました。", "Make yourself understood.", "一切准备就绪。"),
                    subtitle: tr("いつものアプリで文章を書いたら、バーにカーソルを合わせてみましょう。", "Write in your usual app, then move your pointer onto the bar.", "在常用应用中输入文字，然后将光标移到工具条上。"))
                Text(tr("文章スタイルは、設定からいつでも変更できます。", "Your writing style is always yours to adjust in Settings.", "你可以随时在设置中调整写作风格。"))
                    .font(Tokens.LightFont.Onboarding.body)
                    .foregroundStyle(Tokens.Window.textSecondary)
            }
        } visual: {
            OnboardingVisualStage(artwork: .glow) {
                OnboardingMascotHero().frame(width: 344, height: 344)
            }
        }
    }
}

private struct StepHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var centered = false
    var titleWeight: Font.Weight = .medium

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 12) {
            if !eyebrow.isEmpty {
                Text(eyebrow).font(Tokens.LightFont.Onboarding.caption)
                    .foregroundStyle(Tokens.Window.textSecondary)
            }
            Text(title).font(Tokens.LightFont.body(32, weight: titleWeight))
                .tracking(-0.5).foregroundStyle(Tokens.Window.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(Tokens.LightFont.Onboarding.body)
                .foregroundStyle(Tokens.Window.textSecondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(centered ? .center : .leading)
    }
}

private struct PillCaption: View {
    var prefix: String = ""
    let suffix: String

    var body: some View {
        PillSentence(before: prefix, after: suffix, scale: 0.52, spacing: 6)
            .font(Tokens.LightFont.body(16, weight: .medium))
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

private struct CompleteStepHeading: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(tr("セットアップ完了", "All set", "设置完成"))
                .font(Tokens.LightFont.body(16, weight: .medium))
                .foregroundStyle(Tokens.Window.accentText)
            Text(tr("準備できました", "You're ready", "准备就绪"))
                .font(Tokens.LightFont.display(28))
                .tracking(Tokens.LightFont.displayTracking(28))
                .foregroundStyle(Tokens.Window.textPrimary)
            Text(tr(
                "文章の入力欄をクリックして、バーから整えましょう。",
                "Click inside your message, then use the bar to polish it.",
                "点击消息输入框，然后使用工具条润色。"
            ))
                .font(Tokens.LightFont.Onboarding.body)
                .foregroundStyle(Tokens.Window.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(tr(
                "このウインドウを閉じても、バーはそのまま使えます。",
                "You can close this window. The bar stays available.",
                "可以关闭此窗口。工具条仍可继续使用。"
            ))
                .font(Tokens.LightFont.Onboarding.body)
                .foregroundStyle(Tokens.Window.textPrimary)
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
                .font(Tokens.LightFont.mono(12))
                .foregroundStyle(Tokens.Window.accentText)
                .frame(width: 22, alignment: .leading)
            Text(text).font(Tokens.LightFont.Onboarding.body).foregroundStyle(Tokens.Window.textPrimary)
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
                .font(Tokens.LightFont.mono(12))
                .foregroundStyle(Tokens.Window.accentText)
                .frame(width: 22, alignment: .leading)
            PillSentence(before: prefix, after: suffix)
                .font(Tokens.LightFont.Onboarding.body)
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
                .font(Tokens.LightFont.Onboarding.body)
                .foregroundStyle(Tokens.Window.textPrimary)
        }
    }
}

private struct OnboardingMascotHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var compact = false
    private var usesStaticPortrait: Bool {
        #if DEBUG
        reduceMotion || AsideDesignPreview.isRunning
        #else
        reduceMotion
        #endif
    }

    var body: some View {
        Group {
            // The bundled clip is HEVC with a premultiplied alpha channel, so it draws
            // straight onto the scenic stage. §15 owns why it is not the source mp4.
            if !usesStaticPortrait, let url = Bundle.main.url(forResource: "OnboardingMascotLoop", withExtension: "mov") {
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

/// The name page's stage: a reply with the name in it, redrawn as the field is typed.
///
/// No bar — this page is not about the bar, and the one moving thing on the stage should
/// be the word the user is entering. The window is **centred at a fixed height rather
/// than filled to the stage's edges** like the practice pages' composer: nothing here
/// is typed into it, so the height it needs is the height of the four lines it holds,
/// and a composer stretched to 500 pt for them is mostly empty white.
private struct NameIllustration: View {
    let name: String

    var body: some View {
        OnboardingVisualStage {
            OnboardingMailWindow {
                OnboardingNameMailBody(name: name)
            }
            .frame(height: 320)
            .padding(.horizontal, 36)
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

#if DEBUG
/// Run the built executable with --render-aside-previews. No production startup,
/// credentials, network requests, analytics initialization, or preference writes.
@MainActor enum AsideDesignPreview {
    static var isRunning: Bool { ProcessInfo.processInfo.arguments.contains("--render-button-previews") || ProcessInfo.processInfo.arguments.contains("--render-aside-previews") || ProcessInfo.processInfo.arguments.contains("--render-hover-previews") || isInspecting }
    static var isInspecting: Bool { ProcessInfo.processInfo.arguments.contains("--inspect-button-setup") }
    private static var inspectionWindow: NSWindow?
    static var state = "ready"
    private struct EmptySession: SessionStoring {
        func read() -> AuthSession? { nil }
        func write(_ session: AuthSession) {}
        func clear() {}
    }
    static func render() async throws {
        let output = URL(fileURLWithPath: "/private/tmp/aside-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let config = SupabaseConfig(supabaseURL: URL(string: "http://127.0.0.1:1")!, authURL: URL(string: "http://127.0.0.1:1")!, publishableKey: "preview", appVersion: "preview")
        let auth = AuthService(config: config, store: EmptySession())
        let history = RewriteHistoryStore(directory: output.appendingPathComponent("isolated-history"))
        let model = MainModel(auth: auth, promptStore: UserPromptRemoteStore(config: config, auth: auth),
            profileStore: ProfileRemoteStore(config: config, auth: auth),
            billingStore: BillingRemoteStore(config: config, auth: auth),
            history: history, appVersion: "preview", onPromptsChanged: {})
        let overlay = OverlayController(rewriteService: DesktopRewriteService(config: config, auth: auth),
            auth: auth, promptStore: UserPromptRemoteStore(config: config, auth: auth), analytics: PostHogAnalytics(), history: history, appVersion: "preview")
        let defaults = UserDefaults(suiteName: "AsideDesignPreview")!
        if ProcessInfo.processInfo.arguments.contains("--render-button-previews") {
            for language in AppLanguage.allCases {
                AppLanguageState.current = language
                model.configureDesignPreview()
                model.configureButtonSetupPreview(accountID: nil, saved: [])
                let coordinator = OnboardingCoordinator(mainModel: model, overlay: overlay,
                    progress: OnboardingProgressStore(defaults: defaults, persistsChanges: false),
                    languageStore: AppLanguageStore(defaults: defaults), onFinish: {})
                for pack in OnboardingPresetPack.available(for: language) {
                    coordinator.configureDesignPreview(step: .purpose)
                    coordinator.select(pack: pack)
                    for index in 0..<4 {
                        try await capture(OnboardingFlowView(coordinator: coordinator, buttonExampleIndex: index),
                            size: NSSize(width: 1080, height: 700),
                            name: "buttons-\(language.rawValue)-\(pack.rawValue)-\(index)", output: output)
                    }
                }
                model.configureButtonSetupPreview(accountID: "preview", saved: OnboardingPresetPack.starter.drafts().enumerated().map { $0.element.userPrompt(at: $0.offset) })
                coordinator.configureDesignPreview(step: .purpose)
                coordinator.selectCurrentButtons()
                try await capture(OnboardingFlowView(coordinator: coordinator), size: NSSize(width: 1080, height: 700),
                    name: "buttons-\(language.rawValue)-returning", output: output)
                coordinator.configureDesignPreview(step: .review)
                try await capture(OnboardingFlowView(coordinator: coordinator), size: NSSize(width: 1080, height: 700),
                    name: "buttons-\(language.rawValue)-editor", output: output)
                for _ in 0..<3 { coordinator.addDraft() }
                coordinator.buttonDrafts[0].title = "A deliberately long button name that wraps to several lines"
                try await capture(OnboardingFlowView(coordinator: coordinator),
                    size: NSSize(width: 1080, height: 700), name: "buttons-\(language.rawValue)-editor-long", output: output)
                for fixture in ["saving", "error"] {
                    coordinator.configureDesignPreview(step: .review, state: fixture)
                    try await capture(OnboardingFlowView(coordinator: coordinator),
                        size: NSSize(width: 1080, height: 700), name: "buttons-\(language.rawValue)-editor-\(fixture)", output: output)
                }
                for size in [NSSize(width: 1000, height: 700), NSSize(width: 920, height: 640)] {
                    for fixture in ["ready", "hidden-long", "empty", "loading", "saving", "error"] {
                        var prompts = OnboardingPresetPack.starter.drafts().enumerated().map { $0.element.userPrompt(at: $0.offset) }
                        if fixture == "hidden-long" {
                            prompts[0].title = "A deliberately long button name that wraps to several lines"
                            prompts[0].isEnabled = false
                            prompts[0].prompt = Array(repeating: prompts[0].prompt, count: 4).joined(separator: "\n\n")
                        }
                        model.configureButtonSetupPreview(accountID: "preview",
                            saved: ["empty", "loading"].contains(fixture) ? [] : prompts,
                            loaded: fixture != "loading", state: fixture)
                        model.page = .buttons
                        model.showsPreferences = false
                        try await capture(MainWindowView(model: model), size: size,
                            name: "buttons-\(language.rawValue)-dashboard-\(fixture)-\(Int(size.width))", output: output)
                    }
                }
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--render-hover-previews") {
            AppLanguageState.current = .english
            let cases: [(String, [String], SnapZone, NSSize)] = [
                ("hover-four", ["Corporate", "Email", "Shorten", "Proofread"], .bottomCenter, NSSize(width: 540, height: 90)),
                ("hover-single", ["A"], .bottomCenter, NSSize(width: 540, height: 90)),
                ("hover-long", Array(repeating: "A deliberately long saved button title", count: 7), .bottomCenter, NSSize(width: 1920, height: 90)),
                ("hover-side", ["Corporate", "Email", "Shorten", "Proofread"], .left, NSSize(width: 200, height: 340))
            ]
            for (name, titles, zone, size) in cases {
                overlay.configureHoverPreview(titles: titles, zone: zone)
                try await capture(HoverRow(controller: overlay)
                    .fixedSize()
                    .background(SmokedGlassSurface(shape: Capsule(), forceOpaque: true))
                    .padding(20), size: size, name: name, output: output)
            }
            return
        }
        if isInspecting {
            AppLanguageState.current = .english
            model.configureDesignPreview()
            let coordinator = OnboardingCoordinator(mainModel: model, overlay: overlay,
                progress: OnboardingProgressStore(defaults: defaults, persistsChanges: false),
                languageStore: AppLanguageStore(defaults: defaults), onFinish: {})
            coordinator.configureDesignPreview(step: .review)
            let host = NSHostingView(rootView: OnboardingFlowView(coordinator: coordinator))
            host.sizingOptions = []
            let size = NSSize(width: 1080, height: 700)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Button setup · isolated preview"
            window.appearance = NSAppearance(named: .aqua)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.setContentSize(size)
            window.center()
            inspectionWindow = window
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var manifest: [String] = []
        for language in AppLanguage.allCases {
            AppLanguageState.current = language
            // Volatile domain: even the language fixture never writes a preference.
            let coordinator = OnboardingCoordinator(mainModel: model, overlay: overlay,
                progress: OnboardingProgressStore(defaults: defaults, persistsChanges: false),
                languageStore: AppLanguageStore(defaults: defaults), onFinish: {})
            for step in DesktopOnboardingStep.flow {
                state = "ready"
                model.configureDesignPreview(signedIn: step != .welcome, state: step == .access ? "permission" : state)
                coordinator.configureDesignPreview(step: step)
                let name = "\(language.rawValue)-onboarding-\(step)"
                try await capture(OnboardingFlowView(coordinator: coordinator), size: NSSize(width: 1080, height: 700), name: name, output: output)
                manifest.append(name)
            }
            for fixture in ["signup", "error", "loading"] {
                state = fixture
                model.configureDesignPreview(signedIn: false, state: fixture)
                coordinator.configureDesignPreview(step: .welcome)
                let name = "\(language.rawValue)-account-\(fixture)"
                try await capture(OnboardingFlowView(coordinator: coordinator), size: NSSize(width: 1080, height: 700), name: name, output: output)
                manifest.append(name)
            }
            state = "ready"
            model.configureDesignPreview()
            for size in [NSSize(width: 1000, height: 700), NSSize(width: 920, height: 640)] {
                for page in [MainModel.Page.home, .buttons, .account] {
                    model.page = page
                    model.showsPreferences = false
                    let name = "\(language.rawValue)-dashboard-\(page)-\(Int(size.width))"
                    try await capture(MainWindowView(model: model), size: size, name: name, output: output)
                    manifest.append(name)
                }
                for section in PreferencesSheet.Section.allCases {
                    model.showsPreferences = true
                    model.preferencesSection = section
                    let name = "\(language.rawValue)-settings-\(section)-\(Int(size.width))"
                    try await capture(MainWindowView(model: model), size: size, name: name, output: output)
                    manifest.append(name)
                }
            }
            model.showsPreferences = false
        }
        try manifest.joined(separator: "\n").write(to: output.appendingPathComponent("manifest.txt"), atomically: true, encoding: .utf8)
        NSLog("Rendered %d Aside design fixtures", manifest.count)
    }

    private static func capture<V: View>(_ view: V, size: NSSize, name: String, output: URL) async throws {
        let host = NSHostingView(rootView: view
            .allowsHitTesting(false)
            .frame(width: size.width, height: size.height))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: output.appendingPathComponent(name + ".png"))
        }
        window.contentView = nil
        window.close()
    }
}
#endif
