import SwiftUI

/// アカウント — one identity across phone and laptop (§6).
///
/// Sign-*up* lives here as well as sign-in: a user who finds the Mac app first should
/// not have to install the keyboard to get an account.
///
/// What is editable is bounded by the table. `profiles` is exactly `id`,
/// `display_name` and `created_at` — there is no plan, avatar or subscription column,
/// so a name, an address and a join date is the whole honest surface. Anything more
/// is a migration in the iOS repo, not a field here.
struct AccountView: View {
    @ObservedObject var model: MainModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageTitle(
                title: "アカウント",
                subtitle: "スマホの敬語ボタンと同じアカウントです。ボタンと契約が共有されます。"
            )

            if model.isSignedIn {
                accountSummary
                profileSection
                syncSection
                sessionSection
            } else {
                authForm
            }
        }
        // Full width, like ホーム and ボタン. The page was clamped to 560 and read as a
        // narrow column hugging the left edge of the window. Fields inside are capped
        // individually instead — an 800 pt email box is its own problem.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Signed in

    private var accountSummary: some View {
        Card(padding: 20) {
            HStack(spacing: 14) {
                Avatar(initial: model.avatarInitial, diameter: 48)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.accountLabel)
                        .font(Tokens.Font.body(15, weight: .semibold))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    if !model.displayName.isEmpty, let email = model.signedInEmail {
                        Text(email)
                            .font(Tokens.Font.body(13))
                            .foregroundStyle(Tokens.Window.textSecondary)
                    }
                    if let joined = model.joinedAt {
                        Text("\(Self.joinedFormatter.string(from: joined)) から利用中")
                            .font(Tokens.Font.body(12))
                            .foregroundStyle(Tokens.Window.textTertiary)
                    }
                }

                Spacer()
                StatusBadge(title: "接続済み", isPositive: true)
            }
        }
    }

    /// One desktop settings group rather than three unrelated cards. The eye can scan
    /// labels down the left and values down the right, which is the same layout Willow
    /// uses for account-like settings in its modal.
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "プロフィール")
            RowGroup {
                SettingsRow(
                    title: "表示名",
                    subtitle: "スマホにも同じ名前が表示されます"
                ) {
                    HStack(spacing: 8) {
                        SettingsField(
                            placeholder: "名前を入力",
                            text: $model.displayNameDraft,
                            onSubmit: { model.saveDisplayName() }
                        )
                        .frame(width: Self.fieldWidth)
                        ActionButton(
                            "保存",
                            style: .primary,
                            enabled: model.canSaveDisplayName
                        ) {
                            model.saveDisplayName()
                        }
                    }
                }
                Hairline()
                SettingsRow(title: "メールアドレス") {
                    Text(model.signedInEmail ?? "—")
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .textSelection(.enabled)
                }
                Hairline()
                SettingsRow(title: "利用開始") {
                    Text(model.joinedAt.map { Self.joinedFormatter.string(from: $0) } ?? "—")
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }
            }
            if let error = model.profileError {
                Text(error)
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textPrimary)
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "同期")
            RowGroup {
                SettingsRow(
                    title: "ボタンと表示名",
                    subtitle: "スマホとこの Mac の両方に反映されます"
                ) {
                    Badge("同期")
                }
                Hairline()
                SettingsRow(
                    title: "履歴と統計",
                    subtitle: "文章の記録はこの端末から出ません"
                ) {
                    Badge("この Mac")
                }
            }
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "セッション")
            RowGroup {
                SettingsRow(
                    title: "この Mac からサインアウト",
                    subtitle: "履歴は端末に残り、同期だけが停止します"
                ) {
                    ActionButton("サインアウト", style: .secondary) { model.signOut() }
                }
            }
        }
    }

    /// Cards run the full width; the editable value does not. A text field as wide as
    /// the pane is harder to read and makes the Save action look detached from it.
    private static let fieldWidth: CGFloat = 280

    private static let joinedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.setLocalizedDateFormatFromTemplate("yMMM")
        return formatter
    }()

    // MARK: - Signed out

    /// A real desktop composition: context and trust on the left, the compact account
    /// form on the right. `ViewThatFits` stacks the same two pieces at the minimum
    /// window width rather than squeezing fields or clipping them.
    private var authForm: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                authIntroduction
                    .frame(width: 220, alignment: .leading)
                authControls
                    .frame(width: Self.authGroupWidth, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 24) {
                authIntroduction
                authControls
                    .frame(maxWidth: Self.authGroupWidth, alignment: .leading)
            }
        }
    }

    private var authIntroduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Badge("共有アカウント")
            VStack(alignment: .leading, spacing: 6) {
                Text("スマホと Mac を、ひとつにつなぐ")
                    .font(Tokens.Font.body(17, weight: .semibold))
                    .foregroundStyle(Tokens.Window.textPrimary)
                Text("同じアカウントでサインインすると、いつものボタンをこの Mac でもすぐに使えます。")
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                AuthBenefit(icon: .buttons, text: "ボタンを自動で同期")
                AuthBenefit(icon: .profile, text: "表示名と契約を共有")
                AuthBenefit(icon: .history, text: "履歴はこの Mac に保存")
            }
        }
    }

    private var authControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ModeTabs(mode: $model.authMode)

            RowGroup {
                SettingsRow(title: "メールアドレス") {
                    SettingsField(placeholder: "you@example.com", text: $model.email) { submit() }
                        .frame(width: Self.authFieldWidth)
                }
                Hairline()
                SettingsRow(
                    title: "パスワード",
                    subtitle: model.authMode == .signUp ? "6文字以上" : nil
                ) {
                    SettingsField(placeholder: "", text: $model.password, secure: true) { submit() }
                        .frame(width: Self.authFieldWidth)
                }
                if model.authMode == .signUp {
                    Hairline()
                    SettingsRow(title: "パスワード（確認）") {
                        SettingsField(
                            placeholder: "",
                            text: $model.passwordConfirm,
                            secure: true,
                            onSubmit: { submit() }
                        )
                        .frame(width: Self.authFieldWidth)
                    }
                }
            }

            if let error = model.authError {
                Text(error)
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = model.authNotice {
                Text(notice)
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                ActionButton(
                    model.authMode == .signIn ? "サインイン" : "アカウントを作成",
                    style: .primary,
                    enabled: canSubmit,
                    action: submit
                )
                ActionButton("Google で続ける", style: .secondary, enabled: !model.isAuthenticating) {
                    model.signInWithGoogle()
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Wide enough for an address, narrow enough that the row still reads as a row.
    private static let authFieldWidth: CGFloat = 240
    private static let authGroupWidth: CGFloat = 460

    private func submit() {
        guard canSubmit else { return }
        if model.authMode == .signIn { model.signIn() } else { model.signUp() }
    }

    private var canSubmit: Bool {
        guard !model.isAuthenticating else { return false }
        return model.email.contains("@") && model.password.count >= 6
    }
}

private struct AuthBenefit: View {
    let icon: Icon.Name
    let text: String

    var body: some View {
        HStack(spacing: 9) {
            IconPlate(icon: icon, diameter: 28, tinted: false)
            Text(text)
                .font(Tokens.Font.body(13, weight: .medium))
                .foregroundStyle(Tokens.Window.textPrimary)
        }
    }
}

private struct StatusBadge: View {
    let title: String
    var isPositive = false

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isPositive ? Tokens.Window.success : Tokens.Window.controlOff)
                .frame(width: 6, height: 6)
            Text(title)
                .font(Tokens.Font.body(12, weight: .medium))
        }
        .foregroundStyle(Tokens.Window.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Tokens.Window.surface))
    }
}

/// `design.md`'s tab row: a quiet track holding two pills, the active one lifted to
/// white with a hairline of its own.
private struct ModeTabs: View {
    @Binding var mode: MainModel.AuthMode

    var body: some View {
        HStack(spacing: 4) {
            tab("サインイン", .signIn)
            tab("新規登録", .signUp)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Window.rowRadius + 3, style: .continuous)
                .fill(Tokens.Window.surface)
        )
        // The track is a control, not a bar: full width it reads as a second navigation
        // strip across the page.
        .fixedSize()
    }

    private func tab(_ title: String, _ value: MainModel.AuthMode) -> some View {
        let isActive = mode == value
        return Button {
            mode = value
        } label: {
            Text(title)
                .font(Tokens.Font.body(13, weight: .medium))
                .foregroundStyle(
                    isActive ? Tokens.Window.textPrimary : Tokens.Window.textSecondary
                )
                .padding(.horizontal, 14)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Window.rowRadius, style: .continuous)
                        .fill(isActive ? Tokens.Window.canvas : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Window.rowRadius, style: .continuous)
                        .strokeBorder(isActive ? Tokens.Window.hairline : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
    }
}
