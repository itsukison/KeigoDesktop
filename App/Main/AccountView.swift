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
                identityCard
                nameSection
                syncSection
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

    private var identityCard: some View {
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
                ActionButton("サインアウト", style: .secondary) { model.signOut() }
            }
        }
    }

    /// The caption sits *outside* the card — `design.md` labels a group by writing
    /// above it, not by putting a title inside the box.
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "表示名")
            Card(padding: 20) {
                HStack(spacing: 10) {
                    SettingsField(
                        placeholder: "名前を入力",
                        text: $model.displayNameDraft,
                        onSubmit: { model.saveDisplayName() }
                    )
                    .frame(maxWidth: Self.fieldWidth)
                    ActionButton("保存", style: .primary, enabled: model.canSaveDisplayName) {
                        model.saveDisplayName()
                    }
                    Spacer(minLength: 0)
                }

                if let error = model.profileError {
                    Text(error)
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textPrimary)
                } else {
                    Text("スマホの敬語ボタンにも同じ名前が表示されます。")
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textTertiary)
                }
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: "同期")
            Card(padding: 20) {
                Text("ボタンと表示名はスマホとこの Mac で共有されます。どちらで編集しても、もう一方に反映されます。履歴と統計はこの Mac にだけ保存されます。")
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Cards run the full width; the inputs inside them do not. A text field as wide
    /// as the window is harder to read, not more generous.
    private static let fieldWidth: CGFloat = 380

    private static let joinedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.setLocalizedDateFormatFromTemplate("yMMM")
        return formatter
    }()

    // MARK: - Signed out

    /// **The form is a row group, not a hero card.**
    ///
    /// What was here was the shape a sign-in page takes when nobody opens `design.md`:
    /// a tinted icon plate and a bold heading *inside* a card, placeholder-only inputs,
    /// a small button, and a 「または」 rule separating it from a Google button that was
    /// sitting right underneath anyway — all wrapped in a full-width card clamped to a
    /// 380 pt column, so half the card was empty. Four of those are in the system's own
    /// Don'ts: don't title a card from inside it when a caption above it will do, don't
    /// leave a card's width unused, carry hierarchy with weight rather than ornament,
    /// and don't put a rule where nothing needs separating.
    ///
    /// The system's form *is* the settings pattern: label-plus-control rows in a
    /// hairline group, with the actions under it. That is what the ⚙︎ modal and the
    /// signed-in half of this page already look like, so signing in now looks like the
    /// rest of the window instead of a landing page dropped into it.
    private var authForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            // No caption over the group: the tabs sit directly on top of it and say
            // which of the two it is, and repeating that in ash underneath them was
            // the same word twice.
            ModeTabs(mode: $model.authMode)

            RowGroup {
                SettingsRow(title: "メールアドレス") {
                    SettingsField(placeholder: "you@example.com", text: $model.email) {
                        submit()
                    }
                    .frame(width: Self.authFieldWidth)
                }
                Hairline()
                SettingsRow(
                    title: "パスワード",
                    subtitle: model.authMode == .signUp ? "6文字以上" : nil
                ) {
                    SettingsField(placeholder: "", text: $model.password, secure: true) {
                        submit()
                    }
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
            // The one place on this page a group is *not* full width. A settings row
            // flings its control to the far edge, which is right for a switch and wrong
            // for a field you are about to type an address into — at the pane's full
            // width the label and its input end up 200 pt apart.
            .frame(maxWidth: Self.authGroupWidth, alignment: .leading)

            // Outside the group, not inside a row: the message is about the whole
            // attempt, and a row group whose height changes as you type is unsettling.
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

            // Two buttons in one row, and no rule between them. The 「または」 divider
            // is the auth-page cliché and it was separating a primary action from an
            // alternative that is right beside it anyway.
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
    private static let authFieldWidth: CGFloat = 300
    private static let authGroupWidth: CGFloat = 540

    private func submit() {
        guard canSubmit else { return }
        if model.authMode == .signIn { model.signIn() } else { model.signUp() }
    }

    private var canSubmit: Bool {
        guard !model.isAuthenticating else { return false }
        return model.email.contains("@") && model.password.count >= 6
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
