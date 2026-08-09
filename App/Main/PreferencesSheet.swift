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
            case .general: return tr("一般", "General", "通用")
            case .plan: return tr("プラン", "Plan", "套餐")
            case .history: return tr("履歴", "History", "历史")
            case .about: return tr("このアプリ", "About", "关于本应用")
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
                RoundIconButton(icon: .close, help: tr("閉じる", "Close", "关闭"), action: dismiss)
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
            group(tr("権限", "Permission", "权限")) {
                SettingsRow(
                    title: tr("アクセシビリティ", "Accessibility", "辅助功能"),
                    subtitle: model.isTrusted
                        ? tr(
                            "編集中の文章を読み書きできます。",
                            "The app can read and replace the text you are editing.",
                            "可以读写正在编辑的文字。"
                        )
                        : tr(
                            "編集中の文章を読み取って書き換えた文章を戻すために必要です。",
                            "Needed to read the text you are editing and write the rewrite back.",
                            "用于读取正在编辑的文字并写回改写结果。"
                        )
                ) {
                    HStack(spacing: 10) {
                        StatusDot(ok: model.isTrusted)
                        if model.isTrusted {
                            Text(tr("許可済み", "Granted", "已授权"))
                                .font(Tokens.Font.body(13))
                                .foregroundStyle(Tokens.Window.textSecondary)
                        } else {
                            ActionButton(tr("許可する", "Grant access", "授予权限"), style: .primary) {
                                model.requestAccessibility()
                            }
                        }
                    }
                }
            }

            group(tr("基本", "Basics", "基本")) {
                // The only entry point for everyone who finished onboarding before
                // §15's language page existed — they are never asked, so this row is
                // the whole answer for them (§17).
                SettingsRow(
                    title: tr("言語", "Language", "语言"),
                    subtitle: tr(
                        "アプリの表示言語です。ボタンの文章は変わりません。",
                        "The app's interface. Your existing buttons are not rewritten.",
                        "应用的界面语言。已有按钮的内容不会改变。"
                    )
                ) {
                    Picker("", selection: Binding(
                        get: { model.language },
                        set: { model.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                            Text(language.endonym).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
                Hairline()
                SettingsRow(
                    title: tr("ログイン時に起動", "Launch at login", "登录时启动"),
                    subtitle: tr(
                        "Mac の起動時に敬語ボタンを開きます。",
                        "Opens KeigoButton when your Mac starts.",
                        "Mac 启动时自动打开敬語ボタン。"
                    )
                ) {
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
                    title: tr("返信モード", "Reply mode", "回复模式"),
                    subtitle: tr(
                        "文章をコピーすると、バーがその文章への返信モードに変わります。",
                        "When you copy a message, the bar switches to composing a reply to it.",
                        "复制文字后，工具栏会切换为对该内容的回复模式。"
                    )
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.replyModeEnabled },
                        set: { model.setReplyModeEnabled($0) }
                    ))
                    .accentSwitch()
                    .labelsHidden()
                }
                Hairline()
                SettingsRow(
                    title: tr("バーの位置", "Bar position", "工具栏位置"),
                    subtitle: tr(
                        "バーはドラッグで移動できます。",
                        "The bar can be dragged anywhere along the bottom.",
                        "可以拖动工具栏来移动位置。"
                    )
                ) {
                    ActionButton(tr("位置をリセット", "Reset position", "重置位置"), style: .secondary) { model.resetPosition() }
                }
            }
        }
    }

    // MARK: - 履歴

    /// The history file holds the user's actual text in the clear, which is what makes
    /// the ホーム list useful and also why both of these controls exist.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            group(tr("保存", "Storage", "保存")) {
                SettingsRow(
                    title: tr("履歴を保存する", "Keep history", "保存历史"),
                    subtitle: tr("ホームの統計と履歴に使われます。", "Used for the stats and history on Home.", "用于主页的统计和历史。")
                ) {
                    Toggle("", isOn: Binding(
                        get: { model.historyEnabled },
                        set: { model.setHistoryEnabled($0) }
                    ))
                    .accentSwitch()
                    .labelsHidden()
                }
                Hairline()
                SettingsRow(
                    title: tr("履歴を消去", "Erase history", "清除历史"),
                    subtitle: tr(
                        "保存されている記録と統計をすべて削除します。",
                        "Deletes every stored rewrite and all statistics.",
                        "删除所有已保存的记录和统计。"
                    )
                ) {
                    ActionButton(tr("消去", "Erase", "清除"), style: .secondary) { confirmingClear = true }
                }
            }

            Text(tr(
                "書き換えた文章はこの Mac の中だけに保存されます。サーバーには送られません。最新の\(RewriteHistoryStore.capacity)件を保持します。",
                "Rewrites are stored only on this Mac and never sent to a server. The most recent \(RewriteHistoryStore.capacity) are kept.",
                "改写内容仅保存在这台 Mac 上，不会发送到服务器。保留最近 \(RewriteHistoryStore.capacity) 条。"
            ))
                .font(Tokens.Font.body(12))
                .foregroundStyle(Tokens.Window.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert(tr("履歴を消去しますか？", "Erase history?", "要清除历史吗？"), isPresented: $confirmingClear) {
            Button(tr("消去", "Erase", "清除"), role: .destructive) { model.clearHistory() }
            Button(tr("キャンセル", "Cancel", "取消"), role: .cancel) {}
        } message: {
            Text(tr(
                "保存されている書き換えの記録と統計がすべて削除されます。元に戻せません。",
                "Every stored rewrite and all statistics will be deleted. This can't be undone.",
                "所有已保存的改写记录和统计都会被删除，且无法撤销。"
            ))
        }
    }

    // MARK: - このアプリ

    private var aboutSection: some View {
        group(tr("敬語ボタン", "KeigoButton", "敬語ボタン")) {
            SettingsRow(title: tr("バージョン", "Version", "版本"), subtitle: nil) {
                Text(model.appVersion)
                    .font(Tokens.Font.mono(13))
                    .foregroundStyle(Tokens.Window.textSecondary)
            }
            Hairline()
            SettingsRow(
                title: tr("終了", "Quit", "退出"),
                subtitle: tr("バーも一緒に閉じます。", "Closes the bar as well.", "同时关闭工具栏。")
            ) {
                ActionButton(tr("敬語ボタンを終了", "Quit KeigoButton", "退出敬語ボタン"), style: .secondary) { NSApp.terminate(nil) }
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
