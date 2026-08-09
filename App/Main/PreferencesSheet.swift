import AppKit
import DesktopRewriteKit
import SwiftUI

/// The ⚙︎ modal: the low-level switches that have nowhere to live on a content page.
///
/// **A centred card over a dimmed window, not an `NSWindow` sheet.** `design.md`'s
/// settings modal floats in the middle of the window behind a 40 % scrim and carries
/// a navigation pane of its own; a real sheet drops from the titlebar, is not dimmed,
/// and cannot be dismissed by clicking away from it. This is an overlay inside the
/// window instead, which is what makes all three of those behaviours available.
///
/// It stays a modal rather than a fourth sidebar destination — these are settings you
/// change once and never look at again, and giving them equal billing with ホーム would
/// misrepresent how often they matter.
struct PreferencesSheet: View {
    @ObservedObject var model: MainModel

    enum Section: String, CaseIterable, Identifiable {
        case general
        case plan
        case history
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "一般"
            case .plan: return "プラン"
            case .history: return "履歴"
            case .about: return "このアプリ"
            }
        }

        var icon: Icon.Name {
            switch self {
            case .general: return .sliders
            case .plan: return .plan
            case .history: return .history
            case .about: return .info
            }
        }
    }

    @State private var confirmingClear = false

    private var section: Section { model.preferencesSection }

    var body: some View {
        ZStack {
            Tokens.Window.scrim
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            card
        }
        // A focused text field elsewhere in the window can swallow Escape, so the
        // shortcut is installed as a real (invisible) cancel button as well.
        .onExitCommand(perform: dismiss)
        .background {
            Button("", action: dismiss)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        }
    }

    private func dismiss() {
        model.showsPreferences = false
    }

    private var card: some View {
        HStack(spacing: 0) {
            nav
            content
        }
        .frame(width: 780, height: 540)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Window.sheetRadius, style: .continuous)
                .fill(Tokens.Window.canvas)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: Tokens.Window.sheetRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.22), radius: 40, y: 12)
    }

    // MARK: - Left pane

    /// `design.md` puts a search field above this list, and a pair of external links
    /// under it. Six switches do not need a search box, and we have no help centre to
    /// link to — a control that never has anything to find or open reads as broken.
    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Section.allCases) { item in
                NavItem(
                    icon: item.icon,
                    title: item.title,
                    isActive: section == item
                ) {
                    model.preferencesSection = item
                }
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 216)
        .frame(maxHeight: .infinity)
        .background(Tokens.Window.group)
    }

    // MARK: - Right pane

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(section.title)
                    .font(Tokens.Font.display(17))
                    .foregroundStyle(Tokens.Window.textPrimary)
                Spacer()
                RoundIconButton(icon: .close, help: "閉じる", action: dismiss)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch section {
                    case .general: generalSection
                    case .plan: PlanView(model: model)
                    case .history: historySection
                    case .about: aboutSection
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 一般

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // §5: the permission is tied to the binary's signature, so a rebuild
            // silently revokes it. `MainModel.refresh()` re-checks on every activation.
            group("権限") {
                SettingsRow(
                    title: "アクセシビリティ",
                    subtitle: model.isTrusted
                        ? "編集中の文章を読み書きできます。"
                        : "編集中の文章を読み取って書き換えた文章を戻すために必要です。"
                ) {
                    HStack(spacing: 10) {
                        StatusDot(ok: model.isTrusted)
                        if model.isTrusted {
                            Text("許可済み")
                                .font(Tokens.Font.body(13))
                                .foregroundStyle(Tokens.Window.textSecondary)
                        } else {
                            ActionButton("許可する", style: .primary) {
                                model.requestAccessibility()
                            }
                        }
                    }
                }
            }

            group("基本") {
                SettingsRow(title: "ログイン時に起動", subtitle: "Mac の起動時に敬語ボタンを開きます。") {
                    Toggle("", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    .accentSwitch()
                    .labelsHidden()
                }
                Hairline()
                // §16. On by default, so it needs a way off: the feature works by
                // watching what the user copies, and that is worth saying out loud
                // rather than burying — the same reasoning as 履歴を保存する.
                SettingsRow(
                    title: "返信モード",
                    subtitle: "文章をコピーすると、バーがその文章への返信モードに変わります。"
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.replyModeEnabled },
                        set: { model.setReplyModeEnabled($0) }
                    ))
                    .accentSwitch()
                    .labelsHidden()
                }
                Hairline()
                SettingsRow(title: "バーの位置", subtitle: "バーはドラッグで移動できます。") {
                    ActionButton("位置をリセット", style: .secondary) { model.resetPosition() }
                }
            }
        }
    }

    // MARK: - 履歴

    /// The history file holds the user's actual text in the clear, which is what makes
    /// the ホーム list useful and also why both of these controls exist.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            group("保存") {
                SettingsRow(
                    title: "履歴を保存する",
                    subtitle: "ホームの統計と履歴に使われます。"
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.historyEnabled },
                        set: { model.setHistoryEnabled($0) }
                    ))
                    .accentSwitch()
                    .labelsHidden()
                }
                Hairline()
                SettingsRow(title: "履歴を消去", subtitle: "保存されている記録と統計をすべて削除します。") {
                    ActionButton("消去", style: .secondary) { confirmingClear = true }
                }
            }

            Text("書き換えた文章はこの Mac の中だけに保存されます。サーバーには送られません。最新の\(RewriteHistoryStore.capacity)件を保持します。")
                .font(Tokens.Font.body(12))
                .foregroundStyle(Tokens.Window.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("履歴を消去しますか？", isPresented: $confirmingClear) {
            Button("消去", role: .destructive) { model.clearHistory() }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("保存されている書き換えの記録と統計がすべて削除されます。元に戻せません。")
        }
    }

    // MARK: - このアプリ

    private var aboutSection: some View {
        group("敬語ボタン") {
            SettingsRow(title: "バージョン", subtitle: nil) {
                Text(model.appVersion)
                    .font(Tokens.Font.mono(13))
                    .foregroundStyle(Tokens.Window.textSecondary)
            }
            Hairline()
            SettingsRow(title: "終了", subtitle: "バーも一緒に閉じます。") {
                ActionButton("敬語ボタンを終了", style: .secondary) { NSApp.terminate(nil) }
            }
        }
    }

    /// A caption above a bordered group of rows — `design.md`'s settings shape.
    private func group<Content: View>(
        _ caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionCaption(text: caption)
            RowGroup(content: content)
        }
    }
}

private struct NavItem: View {
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
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Window.rowRadius, style: .continuous)
                    .strokeBorder(isActive ? Tokens.Window.hairline : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .cursor(.pointingHand)
    }

    private var fill: Color {
        if isActive { return Tokens.Window.canvas }
        return hovering ? Tokens.Window.canvas.opacity(0.6) : .clear
    }
}
