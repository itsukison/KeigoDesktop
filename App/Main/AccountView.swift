import DesktopRewriteKit
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
                title: tr("アカウント", "Account", "账户"),
                subtitle: tr(
                    "スマホの敬語ボタンと同じアカウントです。ボタンと契約が共有されます。",
                    "The same account as the app on your phone. Buttons and subscription are shared.",
                    "与手机上敬語ボタン使用同一账户。按钮和订阅共享。"
                )
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
                        Text({
                            let date = Self.joinedFormatter.string(from: joined)
                            return tr("\(date) から利用中", "Member since \(date)", "\(date) 起使用")
                        }())
                            .font(Tokens.Font.body(12))
                            .foregroundStyle(Tokens.Window.textTertiary)
                    }
                }

                Spacer()
                StatusBadge(title: tr("接続済み", "Connected", "已连接"), isPositive: true)
            }
        }
    }

    /// One desktop settings group rather than three unrelated cards. The eye can scan
    /// labels down the left and values down the right, which is the same layout Willow
    /// uses for account-like settings in its modal.
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: tr("プロフィール", "Profile", "个人资料"))
            RowGroup {
                SettingsRow(
                    title: tr("メッセージで使う名前", "Name used in messages", "消息中使用的名字"),
                    subtitle: tr(
                        "あなたへの呼びかけの判別と、必要なメール署名に使います",
                        "Recognizes references to you and signs emails when appropriate",
                        "用于识别对你的称呼，并在适当时用于邮件署名"
                    )
                ) {
                    HStack(spacing: 8) {
                        SettingsField(
                            placeholder: tr("名前を入力", "Your name", "输入名称"),
                            text: $model.displayNameDraft,
                            onSubmit: { model.saveDisplayName() }
                        )
                        .frame(width: Self.fieldWidth)
                        ActionButton(
                            tr("保存", "Save", "保存"),
                            style: .primary,
                            enabled: model.canSaveDisplayName
                        ) {
                            model.saveDisplayName()
                        }
                    }
                }
                Hairline()
                SettingsRow(title: tr("メールアドレス", "Email address", "邮箱地址")) {
                    Text(model.signedInEmail ?? "—")
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .textSelection(.enabled)
                }
                Hairline()
                SettingsRow(title: tr("利用開始", "Joined", "开始使用")) {
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
            SectionCaption(text: tr("同期", "Sync", "同步"))
            RowGroup {
                SettingsRow(
                    title: tr("ボタンと表示名", "Buttons and display name", "按钮与显示名称"),
                    subtitle: tr("スマホとこの Mac の両方に反映されます", "Applied on both your phone and this Mac", "会同时应用到手机和这台 Mac")
                ) {
                    Badge(tr("同期", "Synced", "同步"))
                }
                Hairline()
                SettingsRow(
                    title: tr("履歴と統計", "History and stats", "历史与统计"),
                    subtitle: tr("文章の記録はこの端末から出ません", "Your text never leaves this Mac", "文字记录不会离开这台设备")
                ) {
                    Badge(tr("この Mac", "This Mac", "这台 Mac"))
                }
            }
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: tr("セッション", "Session", "会话"))
            RowGroup {
                SettingsRow(
                    title: tr("この Mac からサインアウト", "Sign out of this Mac", "从这台 Mac 退出登录"),
                    subtitle: tr("履歴は端末に残り、同期だけが停止します", "History stays on the Mac; only syncing stops", "历史保留在本机，仅停止同步")
                ) {
                    ActionButton(tr("サインアウト", "Sign out", "退出登录"), style: .secondary) { model.signOut() }
                }
            }
        }
    }

    /// Cards run the full width; the editable value does not. A text field as wide as
    /// the pane is harder to read and makes the Save action look detached from it.
    /// One width for every field on this page — the signed-out form used to carry a
    /// second (240) because it lived in a 460 pt column of its own.
    private static let fieldWidth: CGFloat = 280

    private static var joinedFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppLanguageState.current.locale
        formatter.setLocalizedDateFormatFromTemplate("yMMM")
        return formatter
    }

    // MARK: - Signed out

    /// The same page, signed out: captioned row groups down one column, exactly like
    /// the signed-in half above it.
    ///
    /// It was a two-column split — a marketing panel on the left, the form on the right
    /// — and the two columns never lined up: the left one had no controls in it, the
    /// right one was pinned to a 460 pt frame inside a pane twice that wide, and the
    /// page changed shape completely at the moment of signing in. One column of the
    /// window's own settings idiom is what the rest of this app already is.
    private var authForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            authControls
            authBenefits
        }
    }

    /// The tabs caption the group. A `SectionCaption` reading 「サインイン」 directly
    /// under a tab already reading 「サインイン」 would be the label twice.
    private var authControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ModeTabs(mode: $model.authMode)

            RowGroup {
                SettingsRow(title: tr("メールアドレス", "Email address", "邮箱地址")) {
                    SettingsField(placeholder: "you@example.com", text: $model.email) { submit() }
                        .frame(width: Self.fieldWidth)
                }
                Hairline()
                SettingsRow(
                    title: tr("パスワード", "Password", "密码"),
                    subtitle: model.authMode == .signUp ? tr("6文字以上", "At least 6 characters", "至少6个字符") : nil
                ) {
                    SettingsField(placeholder: "", text: $model.password, secure: true) { submit() }
                        .frame(width: Self.fieldWidth)
                }
                if model.authMode == .signUp {
                    Hairline()
                    SettingsRow(title: tr("パスワード（確認）", "Confirm password", "确认密码")) {
                        SettingsField(
                            placeholder: "",
                            text: $model.passwordConfirm,
                            secure: true,
                            onSubmit: { submit() }
                        )
                        .frame(width: Self.fieldWidth)
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
                    model.authMode == .signIn
                        ? tr("サインイン", "Sign in", "登录")
                        : tr("アカウントを作成", "Create account", "创建账户"),
                    style: .primary,
                    enabled: canSubmit,
                    action: submit
                )
                GoogleSignInButton(size: .inline, isLoading: model.isAuthenticating) {
                    model.signInWithGoogle()
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// What signing in actually does, in the same rows-and-badges shape `syncSection`
    /// uses once signed in — so the page answers the same question before and after,
    /// rather than making the claim in a marketing column that then disappears.
    private var authBenefits: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: tr("サインインすると", "When you sign in", "登录后"))
            RowGroup {
                SettingsRow(
                    title: tr("ボタンが自動で同期されます", "Your buttons sync automatically", "按钮会自动同步"),
                    subtitle: tr("スマホで作ったボタンが、この Mac のバーにそのまま並びます", "The buttons you made on your phone appear on this Mac's bar", "在手机上创建的按钮会直接出现在这台 Mac 的工具栏上")
                ) {
                    Badge(tr("同期", "Synced", "同步"))
                }
                Hairline()
                SettingsRow(
                    title: tr("表示名と契約を共有します", "Name and subscription are shared", "共享显示名称与订阅"),
                    subtitle: tr("アカウントはスマホとこの Mac で共通です", "One account across your phone and this Mac", "手机与这台 Mac 使用同一账户")
                ) {
                    Badge(tr("同期", "Synced", "同步"))
                }
                Hairline()
                SettingsRow(
                    title: tr("履歴と統計はこの Mac に残ります", "History and stats stay on this Mac", "历史与统计保留在这台 Mac"),
                    subtitle: tr("文章の記録はこの端末から出ません", "Your text never leaves this Mac", "文字记录不会离开这台设备")
                ) {
                    Badge(tr("この Mac", "This Mac", "这台 Mac"))
                }
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        if model.authMode == .signIn { model.signIn() } else { model.signUp() }
    }

    private var canSubmit: Bool {
        guard !model.isAuthenticating else { return false }
        return model.email.contains("@") && model.password.count >= 6
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
            tab(tr("サインイン", "Sign in", "登录"), .signIn)
            tab(tr("新規登録", "Create account", "注册"), .signUp)
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
