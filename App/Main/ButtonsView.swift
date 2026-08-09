import DesktopRewriteKit
import SwiftUI

/// ボタン — one ordered desktop list backed by the shared `user_prompts` rows.
///
/// The first row owns the phone's `main` slot. Reordering is deliberately explicit:
/// the compact arrows move one row at a time, without a detached drag preview or hidden
/// drop target competing with the row's toggle and edit controls.
struct ButtonsView: View {
    @ObservedObject var model: MainModel

    static let rowHeight: CGFloat = 60

    @State private var pendingDelete: UserPrompt?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            PageTitle(
                title: tr("ボタン", "Buttons", "按钮"),
                subtitle: tr(
                    "バーに並ぶ書き換えボタンです。変更はスマホにも同期されます。",
                    "The buttons on your bar. Changes sync to your phone too.",
                    "这些是工具栏上的改写按钮。修改会同步到手机。"
                )
            )

            if !model.isSignedIn {
                signInPrompt
            } else {
                toolbar
                if let error = model.promptsError {
                    Text(error)
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }
                promptList
            }
        }
        .alert(item: $pendingDelete) { prompt in
            Alert(
                title: Text(tr("「\(prompt.title)」を削除しますか？", "Delete \u{201C}\(prompt.title)\u{201D}?", "要删除「\(prompt.title)」吗？")),
                message: Text(tr(
                    "このボタンはスマホからも消えます。元に戻せません。",
                    "It disappears from your phone as well, and this can't be undone.",
                    "该按钮也会从手机上消失，且无法撤销。"
                )),
                primaryButton: .destructive(Text(tr("削除", "Delete", "删除"))) { model.delete(prompt) },
                secondaryButton: .cancel(Text(tr("キャンセル", "Cancel", "取消")))
            )
        }
    }

    private var signInPrompt: some View {
        Card(padding: 20) {
            HStack(spacing: 14) {
                IconPlate(icon: .profile, diameter: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("サインインするとボタンを編集できます", "Sign in to edit your buttons", "登录后即可编辑按钮"))
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(tr(
                        "スマホの敬語ボタンと同じアカウントで同期されます。",
                        "They sync with the same account you use on your phone.",
                        "与手机上敬語ボタン使用同一账户同步。"
                    ))
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }
                Spacer()
                ActionButton(tr("サインイン", "Sign in", "登录"), style: .primary) { model.page = .account }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Text({
                let shown = model.prompts.filter(\.isEnabled).count
                let total = model.prompts.count
                return tr(
                    "\(shown) / \(total) 個をバーに表示中",
                    "\(shown) of \(total) shown on the bar",
                    "工具栏上显示 \(shown) / \(total) 个"
                )
            }())
                .font(Tokens.Font.body(13))
                .foregroundStyle(Tokens.Window.textTertiary)
            Spacer()
            ActionButton(tr("ボタンを追加", "Add a button", "添加按钮"), icon: .add, style: .primary) {
                model.addPrompt()
            }
        }
    }

    @ViewBuilder
    private var promptList: some View {
        if model.prompts.isEmpty {
            Card(padding: 20) {
                HStack(spacing: 14) {
                    IconPlate(icon: .buttons, diameter: 40)
                    Text(
                        model.isLoadingPrompts
                            ? tr("読み込んでいます…", "Loading…", "正在加载…")
                            : tr(
                                "まだボタンがありません。「ボタンを追加」から作成できます。",
                                "No buttons yet. Create one with Add a button.",
                                "还没有按钮。可以点击「添加按钮」创建。"
                            )
                    )
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    Spacer()
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionCaption(text: tr("表示順", "Order", "显示顺序"))
                    Spacer(minLength: 12)
                    Text(tr(
                        "先頭がメイン・左の矢印で並べ替え",
                        "First row is the main button — reorder with the arrows",
                        "第一行为主按钮，用左侧箭头排序"
                    ))
                        .font(Tokens.Font.body(11))
                        .foregroundStyle(Tokens.Window.textTertiary)
                }

                RowGroup {
                    ForEach(model.prompts) { prompt in
                        if model.editingPromptId == prompt.id {
                            PromptEditor(
                                prompt: prompt,
                                onSave: { model.save($0); model.editingPromptId = nil },
                                onDelete: {
                                    model.editingPromptId = nil
                                    pendingDelete = prompt
                                },
                                onCancel: { model.editingPromptId = nil }
                            )
                            .id(prompt.id)
                            if prompt.id != model.prompts.last?.id { Hairline() }
                        } else {
                            PromptRow(
                                prompt: prompt,
                                isMain: prompt.id == model.prompts.first?.id,
                                showsSeparator: prompt.id != model.prompts.last?.id,
                                canMoveUp: prompt.id != model.prompts.first?.id,
                                canMoveDown: prompt.id != model.prompts.last?.id,
                                onToggle: { model.setEnabled(prompt, $0) },
                                onMoveUp: { model.movePrompt(id: prompt.id, by: -1) },
                                onMoveDown: { model.movePrompt(id: prompt.id, by: 1) },
                                onEdit: { model.editingPromptId = prompt.id },
                                onDelete: { pendingDelete = prompt }
                            )
                        }
                    }
                }
                // The source of truth changes once per click; no row follows the pointer.
                .animation(.easeOut(duration: 0.16), value: model.prompts.map(\.id))
            }
        }
    }
}

private struct PromptRow: View {
    let prompt: UserPrompt
    let isMain: Bool
    let showsSeparator: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggle: @MainActor @Sendable (Bool) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                IconButton(
                    icon: .arrowUp,
                    help: isMain ? tr("これが先頭です", "Already first", "已在最前") : tr("1つ上へ", "Move up", "上移一位"),
                    enabled: canMoveUp,
                    action: onMoveUp
                )
                IconButton(
                    icon: .arrowDown,
                    help: canMoveDown ? tr("1つ下へ", "Move down", "下移一位") : tr("これが末尾です", "Already last", "已在最后"),
                    enabled: canMoveDown,
                    action: onMoveDown
                )
            }
            .frame(width: 26)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tr("表示順を変更", "Change order", "更改顺序"))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.title)
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    if isMain { Badge(tr("メイン", "Main", "主要")) }
                }
                Text(prompt.prompt.isEmpty ? tr("指示が未入力です", "No instruction yet", "尚未输入指令") : prompt.prompt)
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(get: { prompt.isEnabled }, set: onToggle))
                .accentSwitch()
                .labelsHidden()

            IconButton(icon: .edit, help: tr("編集", "Edit", "编辑"), action: onEdit)
            IconButton(icon: .trash, help: tr("削除", "Delete", "删除"), action: onDelete)
        }
        .padding(.horizontal, 16)
        .frame(height: ButtonsView.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Window.smallCardRadius, style: .continuous)
                .fill(hovering ? Tokens.Window.surface : .clear)
        )
        .overlay(alignment: .bottom) {
            if showsSeparator { Hairline() }
        }
        .opacity(prompt.isEnabled ? 1 : 0.55)
        .onHover { hovering = $0 }
    }
}

/// Inline rather than a sheet: the prompt text is the thing being compared against
/// its neighbours, and a modal hides exactly that.
private struct PromptEditor: View {
    let prompt: UserPrompt
    let onSave: (UserPrompt) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var text: String

    init(
        prompt: UserPrompt,
        onSave: @escaping (UserPrompt) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _title = State(initialValue: prompt.title)
        _text = State(initialValue: prompt.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("ボタン名", "Button name", "按钮名称"))
                    .font(Tokens.Font.body(12, weight: .medium))
                    .foregroundStyle(Tokens.Window.textSecondary)
                SettingsField(placeholder: tr("敬語", "Polite", "敬語"), text: $title)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("指示", "Instruction", "指令"))
                    .font(Tokens.Font.body(12, weight: .medium))
                    .foregroundStyle(Tokens.Window.textSecondary)
                TextEditor(text: $text)
                    .font(Tokens.Font.body(14))
                    .scrollContentBackground(.hidden)
                    .frame(height: 96)
                    .padding(6)
                    .background(FieldBackground())
                Text(tr(
                    "選択した文章をどう書き換えるかを日本語で書きます。例：「取引先に送る丁寧な敬語に直してください。」",
                    "Describe how the text should be rewritten. For example: \u{201C}Rewrite this as a polite email to a client.\u{201D}",
                    "用文字描述要如何改写选中的内容。例如：「请改写成发给客户的礼貌敬语。」"
                ))
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                ActionButton(tr("削除", "Delete", "删除"), style: .secondary, action: onDelete)
                Spacer()
                ActionButton(tr("キャンセル", "Cancel", "取消"), style: .secondary, action: onCancel)
                ActionButton(tr("保存", "Save", "保存"), style: .primary, enabled: !trimmedTitle.isEmpty) {
                    var next = prompt
                    next.title = trimmedTitle
                    next.prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(next)
                }
            }
        }
        .padding(16)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
