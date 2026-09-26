import DesktopRewriteKit
import SwiftUI

/// Translucent desktop glass frames a stable, opaque workspace.
struct MainWindowView: View {
    @ObservedObject var model: MainModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            contentPanel
        }
        // **The window's own paddings are the only ones.** `NSHostingView` under a
        // `fullSizeContentView` window hands SwiftUI a top safe-area inset the height
        // of the titlebar, which was silently added to both columns: the panel's
        // 32 pt top read as ~60 against a 32 pt bottom, and the sidebar's brand row
        // sat that much below where the traffic lights needed it to.
        .ignoresSafeArea()
        .background { AsideSidebarBackdrop().ignoresSafeArea() }
        .disabled(model.showsPreferences)
        // An overlay rather than `.sheet`, so the modal can be centred, dimmed and
        // dismissed by clicking away from it — see `PreferencesSheet`.
        .overlay {
            if model.showsPreferences {
                PreferencesSheet(model: model)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.showsPreferences)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AppMark(size: 22)
                Text(tr("敬語ボタン", "KeigoButton", "敬語ボタン"))
                    .font(Tokens.LightFont.body(15, weight: .semibold))
                    .foregroundStyle(Tokens.Window.textPrimary)
            }
            .padding(.horizontal, 16)
            // Clears the transparent titlebar's traffic lights, which sit over the
            // sidebar rather than over the panel.
            .padding(.top, 36)
            .padding(.bottom, 20)

            VStack(spacing: 2) {
                NavRow(icon: .home, title: tr("ホーム", "Home", "主页"), isActive: model.page == .home) {
                    model.leaveButtons { model.page = .home }
                }
                NavRow(
                    icon: .buttons,
                    title: tr("ボタン", "Buttons", "按钮"),
                    isActive: model.page == .buttons
                ) {
                    model.leaveButtons { model.page = .buttons }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 24)

            accountBlock
        }
        .frame(width: Tokens.Window.sidebarWidth)
        .frame(maxHeight: .infinity)

    }

    /// Pinned bottom-left, and the way into the account page.
    ///
    /// `design.md` stacks a promo pill and a plan card above this row; both are
    /// billing surfaces, and `profiles` carries no plan column (§14), so the row
    /// stands alone rather than sitting under an invented one.
    private var accountBlock: some View {
        HStack(spacing: 10) {
            Button {
                model.leaveButtons { model.page = .account }
            } label: {
                HStack(spacing: 10) {
                    Avatar(initial: model.avatarInitial, diameter: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.accountLabel)
                            .font(Tokens.LightFont.body(13, weight: .medium))
                            .foregroundStyle(Tokens.Window.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(model.isSignedIn ? tr("アカウント", "Account", "账户") : tr("サインイン", "Sign in", "登录"))
                            .font(Tokens.LightFont.body(11))
                            .foregroundStyle(Tokens.Window.textOnSidebar)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)

            IconButton(icon: .settings, help: tr("環境設定", "Settings", "偏好设置")) {
                model.leaveButtons { model.showsPreferences = true }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: - Content

    private var contentPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                switch model.page {
                case .home:
                    HomeView(model: model)
                case .buttons:
                    ButtonsView(model: model)
                case .account:
                    AccountView(model: model)
                }
            }
            .padding(.horizontal, Tokens.Window.pagePadding)
            // The titlebar's drag region runs the full width of the window, so the
            // panel's own first row has to start below it.
            .padding(.top, 32)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Window.panelRadius, style: .continuous)
                .fill(Tokens.Window.canvas)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: Tokens.Window.panelRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.06), radius: 6, y: 1)
        .padding(.top, Tokens.Window.panelInset)
        .padding(.trailing, Tokens.Window.panelInset)
        .padding(.bottom, Tokens.Window.panelInset)
    }
}

/// White selection lifts above the translucent navigation.
private struct NavRow: View {
    let icon: Icon.Name
    let title: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(icon, size: 17)
                    .frame(width: 18)
                    .opticalCentre()
                Text(title)
                    .font(Tokens.LightFont.body(14, weight: isActive ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? Tokens.Window.textPrimary : Tokens.Window.textOnSidebar)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Window.rowRadius, style: .continuous)
                    .fill(fill)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
    }

    private var fill: Color {
        if isActive { return Tokens.Window.rowActive }
        return hovering ? Tokens.Window.rowActive.opacity(0.5) : .clear
    }
}
