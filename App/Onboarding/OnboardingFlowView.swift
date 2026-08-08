import AppKit
import DesktopRewriteKit
import SwiftUI

struct OnboardingFlowView: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    private var model: MainModel { coordinator.mainModel }

    var body: some View {
        VStack(spacing: 0) {
            ProgressRail(step: coordinator.step)
                .padding(.horizontal, 48)
                .padding(.top, 22)
                .padding(.bottom, 14)

            Group {
                switch coordinator.step {
                case .welcome: WelcomeStep(coordinator: coordinator)
                case .access: AccessStep(coordinator: coordinator)
                case .bar: BarStep(coordinator: coordinator)
                case .practice: PracticeStep(coordinator: coordinator)
                case .complete: CompleteStep(coordinator: coordinator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Tokens.Window.shell)
        .onExitCommand {
            if coordinator.step != .welcome { coordinator.back() }
        }
    }
}

private struct ProgressRail: View {
    let step: DesktopOnboardingStep

    private let labels = ["ようこそ", "アクセス", "バー", "練習", "完了"]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                VStack(alignment: .leading, spacing: 7) {
                    Text(label)
                        .font(Tokens.Font.body(11, weight: index == step.rawValue ? .medium : .regular))
                        .foregroundStyle(index <= step.rawValue ? Tokens.Window.accentText : Tokens.Window.textTertiary)
                    Capsule()
                        .fill(index <= step.rawValue ? Tokens.Window.accent : Tokens.Window.hairline)
                        .frame(height: 3)
                }
            }
        }
    }
}

private struct WelcomeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @ObservedObject private var model: MainModel

    init(coordinator: OnboardingCoordinator) {
        self.coordinator = coordinator
        self.model = coordinator.mainModel
    }

    var body: some View {
        HStack(spacing: 54) {
            VStack(alignment: .leading, spacing: 22) {
                AppMark(size: 22)
                VStack(alignment: .leading, spacing: 10) {
                    Text("どのアプリの文章も、\nその場で整える。")
                        .font(Tokens.Font.display(32))
                        .tracking(Tokens.Font.displayTracking(32))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text("敬語ボタンは、いま編集中の文章を読み取り、\n整えた文章を同じ場所へ戻します。")
                        .font(Tokens.Font.body(14))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineSpacing(5)
                }

                if model.isSignedIn {
                    connectedCard
                    ActionButton("続ける", style: .primary) {
                        coordinator.advance()
                    }
                } else {
                    authCard
                }
            }
            .frame(width: 430, alignment: .leading)

            HeroComposition()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 64)
        .padding(.bottom, 44)
    }

    private var connectedCard: some View {
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Tokens.Window.canvas))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tokens.Window.hairline))
    }

    private var authCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $model.authMode) {
                Text("サインイン").tag(MainModel.AuthMode.signIn)
                Text("新規登録").tag(MainModel.AuthMode.signUp)
            }
            .pickerStyle(.segmented)

            SettingsField(placeholder: "メールアドレス", text: $model.email)
            SettingsField(placeholder: "パスワード", text: $model.password, secure: true)
            if model.authMode == .signUp {
                SettingsField(placeholder: "パスワード（確認）", text: $model.passwordConfirm, secure: true)
            }

            if let error = model.authError {
                Text(error).font(Tokens.Font.body(12)).foregroundStyle(Tokens.Window.textPrimary)
            }
            if let notice = model.authNotice {
                Text(notice).font(Tokens.Font.body(12)).foregroundStyle(Tokens.Window.textSecondary)
            }

            HStack(spacing: 10) {
                ActionButton(
                    model.authMode == .signIn ? "サインイン" : "アカウントを作成",
                    enabled: canSubmit
                ) {
                    if model.authMode == .signIn { model.signIn() } else { model.signUp() }
                }
                ActionButton("Google で続ける", style: .secondary, enabled: !model.isAuthenticating) {
                    model.signInWithGoogle()
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Tokens.Window.canvas))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.Window.hairline))
    }

    private var canSubmit: Bool {
        !model.isAuthenticating && model.email.contains("@") && model.password.count >= 6
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
        HStack(spacing: 64) {
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

                HStack(spacing: 10) {
                    if !model.isTrusted {
                        ActionButton("許可する", style: .primary) { model.requestAccessibility() }
                        ActionButton("システム設定を開く", style: .secondary) { openAccessibilitySettings() }
                    } else {
                        ActionButton("続ける") { coordinator.advance() }
                    }
                }
            }
            .frame(width: 450, alignment: .leading)

            PermissionIllustration(granted: model.isTrusted)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 72)
        .padding(.bottom, 54)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
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
        HStack(spacing: 60) {
            VStack(alignment: .leading, spacing: 24) {
                StepHeading(
                    eyebrow: "いつもの使い方",
                    title: "画面下のバーが、いつでも待っています",
                    subtitle: "入力欄に文章を置いたまま、画面下のピルへカーソルを動かします。入力欄のフォーカスは失われません。"
                )

                VStack(alignment: .leading, spacing: 14) {
                    TeachingRow(number: "1", text: "バーにカーソルを合わせて開く")
                    TeachingRow(number: "2", text: "ラベルを押して書き換える")
                    TeachingRow(number: "3", text: "結果を確認して Insert")
                    TeachingRow(number: "✎", text: "自由な指示をその場で入力")
                }

                HStack(spacing: 12) {
                    ActionButton("練習する") { coordinator.advance() }
                    LinkButton(title: "あとで始める") { coordinator.skipEducation() }
                }
            }
            .frame(width: 430, alignment: .leading)

            BarIllustration(prompts: model.prompts.enabledForHoverRow)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 72)
        .padding(.bottom, 54)
    }
}

private struct PracticeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var sample = "明日の会議、15時に変更しといて"
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 22) {
            StepHeading(
                eyebrow: "実際に試す",
                title: coordinator.tutorialCompleted ? "書き戻せました" : "選択せず、そのまま書き換えてみましょう",
                subtitle: coordinator.tutorialCompleted
                    ? "いまの操作が、ほかのアプリでも同じように使えます。"
                    : "下の入力欄にフォーカスを残したまま、画面下のバーを開き「敬語」を押してください。結果が出たら Insert を押します。"
            )
            .frame(maxWidth: 660, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "text.cursor")
                    Text("練習用メッセージ")
                        .font(Tokens.Font.body(13, weight: .medium))
                    Spacer()
                    if coordinator.tutorialCompleted {
                        Label("挿入済み", systemImage: "checkmark.circle.fill")
                            .font(Tokens.Font.body(12, weight: .medium))
                            .foregroundStyle(Tokens.Window.success)
                    }
                }
                .foregroundStyle(Tokens.Window.textSecondary)

                TextEditor(text: $sample)
                    .font(Tokens.Font.body(16))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(14)
                    .focused($focused)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.Window.canvas))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(focused ? Tokens.Window.textPrimary : Tokens.Window.hairline, lineWidth: focused ? 2 : 1)
                    )
                    .frame(height: 150)
                    .accessibilityLabel("練習用メッセージ")
            }
            .padding(18)
            .frame(maxWidth: 660)
            .background(RoundedRectangle(cornerRadius: 18).fill(Tokens.Window.group))

            HStack(spacing: 14) {
                ActionButton("次へ", enabled: coordinator.tutorialCompleted) {
                    coordinator.advance()
                }
                LinkButton(title: "あとで始める") { coordinator.skipEducation() }
            }
        }
        .padding(.bottom, 52)
        .onAppear { focused = true }
    }
}

private struct CompleteStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator

    var body: some View {
        HStack(spacing: 58) {
            VStack(alignment: .leading, spacing: 24) {
                IconPlate(icon: .check, diameter: 48)
                StepHeading(
                    eyebrow: "セットアップ完了",
                    title: "準備できました",
                    subtitle: "文章にフォーカスを置き、画面下のバーを開くだけです。ウインドウを閉じても、敬語ボタンはメニューバーと画面下に残ります。"
                )
                VStack(alignment: .leading, spacing: 10) {
                    CompletionRow(text: "アカウントとボタンを同期")
                    CompletionRow(text: "アクセシビリティを許可")
                    CompletionRow(text: "書き換えの操作を確認")
                }
                ActionButton("敬語ボタンを使う") {
                    coordinator.advance()
                }
            }
            .frame(width: 430, alignment: .leading)

            HeroComposition(compact: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 72)
        .padding(.bottom, 54)
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
                .font(Tokens.Font.display(28))
                .tracking(Tokens.Font.displayTracking(28))
                .foregroundStyle(Tokens.Window.textPrimary)
            Text(subtitle)
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
                .font(Tokens.Font.body(12, weight: .semibold))
                .foregroundStyle(Tokens.Window.accentText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Tokens.Window.accentTint))
            Text(text).font(Tokens.Font.body(14)).foregroundStyle(Tokens.Window.textPrimary)
        }
    }
}

private struct CompletionRow: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .font(Tokens.Font.body(14))
            .foregroundStyle(Tokens.Window.textPrimary)
            .symbolRenderingMode(.palette)
            .foregroundStyle(Tokens.Window.success, Tokens.Window.success)
    }
}

private struct HeroComposition: View {
    var compact = false

    var body: some View {
        ZStack {
            Image("OnboardingHero")
                .resizable()
                .scaledToFill()
                .frame(width: compact ? 390 : 430, height: compact ? 390 : 470)
                .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))

            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.92))
                    .frame(width: 240, height: 145)
                    .overlay(
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 5) {
                                Circle().fill(Color.red.opacity(0.7)).frame(width: 7, height: 7)
                                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 7, height: 7)
                                Circle().fill(Color.green.opacity(0.7)).frame(width: 7, height: 7)
                            }
                            ForEach([0.8, 0.62, 0.72], id: \.self) { width in
                                Capsule().fill(Tokens.Window.hairline).frame(width: 170 * width, height: 7)
                            }
                            Spacer()
                        }
                        .padding(15)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 20, y: 8)

                HStack(spacing: 8) {
                    Image(systemName: "wand.and.sparkles")
                    Text("敬語   自然に   メール")
                        .font(Tokens.Font.body(11, weight: .medium))
                }
                .foregroundStyle(Tokens.Overlay.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(Tokens.Overlay.canvas))
                .shadow(color: .black.opacity(0.24), radius: 14, y: 6)
            }
        }
    }
}

private struct PermissionIllustration: View {
    let granted: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 8, height: 8)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 8, height: 8)
                Circle().fill(Color.green.opacity(0.7)).frame(width: 8, height: 8)
                Text("プライバシーとセキュリティ")
                    .font(Tokens.Font.body(12, weight: .medium))
                    .padding(.leading, 8)
            }
            Hairline()
            HStack(spacing: 12) {
                AppMark(size: 17)
                Text("敬語ボタン").font(Tokens.Font.body(14, weight: .medium))
                Spacer()
                Image(systemName: granted ? "checkmark.circle.fill" : "switch.2")
                    .foregroundStyle(granted ? Tokens.Window.success : Tokens.Window.textTertiary)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.Window.surface))
            Text("許可の変更は自動で検出されます。")
                .font(Tokens.Font.body(12))
                .foregroundStyle(Tokens.Window.textTertiary)
        }
        .padding(22)
        .frame(width: 390, height: 250, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20).fill(Tokens.Window.canvas))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Tokens.Window.hairline))
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct BarIllustration: View {
    let prompts: [UserPrompt]
    private var labels: [String] {
        let titles = prompts.prefix(4).map(\.title)
        return titles.isEmpty ? ["敬語", "自然に", "メール", "英訳"] : titles
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 24)
                .fill(Tokens.Window.canvas)
                .overlay(
                    VStack(alignment: .leading, spacing: 12) {
                        Text("入力中のメッセージ")
                            .font(Tokens.Font.body(12, weight: .medium))
                            .foregroundStyle(Tokens.Window.textTertiary)
                        Text("明日の会議、15時に変更しといて")
                            .font(Tokens.Font.body(16))
                            .foregroundStyle(Tokens.Window.textPrimary)
                        Spacer()
                    }
                    .padding(22)
                )
                .shadow(color: .black.opacity(0.06), radius: 18, y: 8)

            HStack(spacing: 8) {
                Image(systemName: "wand.and.sparkles")
                Rectangle().fill(Tokens.Overlay.hairline).frame(width: 1, height: 15)
                ForEach(labels, id: \.self) { label in
                    Text(label).font(Tokens.Font.body(11, weight: .medium))
                }
                Rectangle().fill(Tokens.Overlay.hairline).frame(width: 1, height: 15)
                Image(systemName: "pencil")
            }
            .foregroundStyle(Tokens.Overlay.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(Tokens.Overlay.canvas))
            .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
            .offset(y: 17)
        }
        .frame(width: 440, height: 310)
        .padding(.bottom, 20)
    }
}

private extension Array where Element == UserPrompt {
    var enabledForHoverRow: [UserPrompt] {
        let main = filter { $0.slot == .main && $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        let sub = filter { $0.slot == .sub && $0.isEnabled }.sorted { $0.sortOrder < $1.sortOrder }
        return main + sub
    }
}
