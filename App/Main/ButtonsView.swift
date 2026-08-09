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
                title: "ボタン",
                subtitle: "バーに並ぶ書き換えボタンです。変更はスマホにも同期されます。"
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
                title: Text("「\(prompt.title)」を削除しますか？"),
                message: Text("このボタンはスマホからも消えます。元に戻せません。"),
                primaryButton: .destructive(Text("削除")) { model.delete(prompt) },
                secondaryButton: .cancel(Text("キャンセル"))
            )
        }
    }

    private var signInPrompt: some View {
        Card(padding: 20) {
            HStack(spacing: 14) {
                IconPlate(icon: .profile, diameter: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("サインインするとボタンを編集できます")
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text("スマホの敬語ボタンと同じアカウントで同期されます。")
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }
                Spacer()
                ActionButton("サインイン", style: .primary) { model.page = .account }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Text("\(model.prompts.filter(\.isEnabled).count) / \(model.prompts.count) 個をバーに表示中")
                .font(Tokens.Font.body(13))
                .foregroundStyle(Tokens.Window.textTertiary)
            Spacer()
            ActionButton("ボタンを追加", icon: .add, style: .primary) {
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
                            ? "読み込んでいます…"
                            : "まだボタンがありません。「ボタンを追加」から作成できます。"
                    )
                    .font(Tokens.Font.body(14))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    Spacer()
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    SectionCaption(text: "表示順")
                    Spacer(minLength: 12)
                    Text("先頭がメイン・左の矢印で並べ替え")
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
                    help: isMain ? "これが先頭です" : "1つ上へ",
                    enabled: canMoveUp,
                    action: onMoveUp
                )
                IconButton(
                    icon: .arrowDown,
                    help: canMoveDown ? "1つ下へ" : "これが末尾です",
                    enabled: canMoveDown,
                    action: onMoveDown
                )
            }
            .frame(width: 26)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("表示順を変更")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.title)
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    if isMain { Badge("メイン") }
                }
                Text(prompt.prompt.isEmpty ? "指示が未入力です" : prompt.prompt)
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(get: { prompt.isEnabled }, set: onToggle))
                .accentSwitch()
                .labelsHidden()

            IconButton(icon: .edit, help: "編集", action: onEdit)
            IconButton(icon: .trash, help: "削除", action: onDelete)
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
                Text("ボタン名")
                    .font(Tokens.Font.body(12, weight: .medium))
                    .foregroundStyle(Tokens.Window.textSecondary)
                SettingsField(placeholder: "敬語", text: $title)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("指示")
                    .font(Tokens.Font.body(12, weight: .medium))
                    .foregroundStyle(Tokens.Window.textSecondary)
                TextEditor(text: $text)
                    .font(Tokens.Font.body(14))
                    .scrollContentBackground(.hidden)
                    .frame(height: 96)
                    .padding(6)
                    .background(FieldBackground())
                Text("選択した文章をどう書き換えるかを日本語で書きます。例：「取引先に送る丁寧な敬語に直してください。」")
                    .font(Tokens.Font.body(12))
                    .foregroundStyle(Tokens.Window.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                ActionButton("削除", style: .secondary, action: onDelete)
                Spacer()
                ActionButton("キャンセル", style: .secondary, action: onCancel)
                ActionButton("保存", style: .primary, enabled: !trimmedTitle.isEmpty) {
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
