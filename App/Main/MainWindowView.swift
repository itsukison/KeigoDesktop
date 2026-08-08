import DesktopRewriteKit
import SwiftUI

/// The window shell: a grey frame, a sidebar drawn straight onto it, and the content
/// as a **white panel floating inside** the frame.
///
/// That panel is `design.md`'s structural signature and the thing that most obviously
/// separates this window from the one it replaces. There is no divider line between
/// the sidebar and the content — the gap of shell colour around the panel *is* the
/// separation, and the panel's own shadow is what puts it in front.
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
        .background(Tokens.Window.shell)
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
                AppMark(size: 15)
                    .opticalCentre()
                Text("敬語ボタン")
                    .font(Tokens.Font.body(15, weight: .semibold))
                    .foregroundStyle(Tokens.Window.textPrimary)
            }
            .padding(.horizontal, 16)
            // Clears the transparent titlebar's traffic lights, which sit over the
            // sidebar rather than over the panel.
            .padding(.top, 36)
            .padding(.bottom, 20)

            VStack(spacing: 2) {
                NavRow(icon: .home, title: "ホーム", isActive: model.page == .home) {
                    model.page = .home
                }
                NavRow(
                    icon: .buttons,
                    title: "ボタン",
                    isActive: model.page == .buttons
                ) {
                    model.page = .buttons
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 24)

            accountBlock
        }
        .frame(width: Tokens.Window.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Tokens.Window.sidebar)
    }

    /// Pinned bottom-left, and the way into the account page.
    ///
    /// `design.md` stacks a promo pill and a plan card above this row; both are
    /// billing surfaces, and `profiles` carries no plan column (§14), so the row
    /// stands alone rather than sitting under an invented one.
    private var accountBlock: some View {
        HStack(spacing: 10) {
            Button {
                model.page = .account
            } label: {
                HStack(spacing: 10) {
                    Avatar(initial: model.avatarInitial, diameter: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.accountLabel)
                            .font(Tokens.Font.body(13, weight: .medium))
                            .foregroundStyle(Tokens.Window.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(model.isSignedIn ? "アカウント" : "サインイン")
                            .font(Tokens.Font.body(11))
                            .foregroundStyle(Tokens.Window.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .cursor(.pointingHand)

            IconButton(icon: .settings, help: "環境設定") {
                model.showsPreferences = true
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

/// The active row **darkens**.
///
/// This reverses the old window's rule, which lifted the active row to the canvas
/// colour on the theory that the lighter surface reads as nearer. `design.md` does
/// the opposite — `#ededef` against a `#f5f6f7` sidebar — and on a sidebar that is
/// already near-white there is no lighter step left to take.
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
                    .font(Tokens.Font.body(14, weight: isActive ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isActive ? Tokens.Window.textPrimary : Tokens.Window.textSecondary)
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
