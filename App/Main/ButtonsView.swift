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
    /// Open only from the language banner. Not a permanent control on this page: for
    /// everyone whose buttons already write the right language there is nothing here to
    /// choose, and a always-visible "replace all my buttons" affordance beside a list of
    /// buttons someone spent time wording is an invitation to lose that work.
    @State private var choosingPack = false

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
                if model.buttonsWriteOtherLanguage {
                    languageMismatchBanner
                }
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
        .sheet(isPresented: $choosingPack) {
            PresetPackPicker(model: model) { choosingPack = false }
        }
    }

    /// Shown when the buttons on this account are stock text for the *other* writing
    /// language — §17's two questions having drifted apart. It is the visible half of
    /// the bug this page could not otherwise explain: an English interface whose 敬語
    /// button returns Japanese, because the instruction behind it is a Japanese sentence
    /// asking for Japanese.
    ///
    /// An offer, never an automatic repair. The rows are shared with the phone and the
    /// user may have chosen them there on purpose, so nothing is written until a pack is
    /// picked in the sheet.
    private var languageMismatchBanner: some View {
        Card(padding: 18) {
            HStack(alignment: .top, spacing: 14) {
                IconPlate(icon: .info, diameter: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr(
                        "ボタンは英語向けの設定になっていません",
                        "These buttons still write Japanese",
                        "这些按钮仍然会写成日语"
                    ))
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    Text(tr(
                        "AIへの指示が日本語で書かれているため、英語を選んでいても日本語で返ってきます。英語向けのセットに入れ替えできます。",
                        "The instruction behind each one asks the AI for Japanese, so a rewrite comes back in Japanese even with English selected. You can swap them for an English set.",
                        "每个按钮给AI的指令都是日语，因此即使界面选了其他语言，改写结果仍是日语。可以替换为对应的按钮组。"
                    ))
                        .font(Tokens.Font.body(13))
                        .foregroundStyle(Tokens.Window.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                ActionButton(
                    tr("セットを選ぶ", "Choose a set", "选择按钮组"),
                    style: .primary
                ) {
                    choosingPack = true
                }
            }
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

/// The pack picker, reached only from ボタン's language banner.
///
/// The same five packs §15's purpose page offers, in the same order, resolved for the
/// current writing language by `OnboardingPresetPack.available(for:)` — so an English
/// user is shown Outreach and Polish where a Japanese one is shown 海外とのやり取り and
/// 日本語を整える. The packs are not translations of one another (§17), which is why this
/// asks rather than converting button by button: there is no English counterpart to 英訳
/// to convert it *into*.
private struct PresetPackPicker: View {
    @ObservedObject var model: MainModel
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("ボタンのセットを選ぶ", "Choose a set of buttons", "选择按钮组"))
                    .font(Tokens.Font.body(16, weight: .semibold))
                    .foregroundStyle(Tokens.Window.textPrimary)
                Text(tr(
                    "選んだ4つに入れ替えます。自分で作ったボタンはそのまま残ります。",
                    "The four you pick replace the preset buttons. Anything you wrote yourself is kept.",
                    "将替换为所选的4个按钮。你自己创建的按钮会保留。"
                ))
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RowGroup {
                let packs = OnboardingPresetPack.available(for: model.language)
                ForEach(Array(packs.enumerated()), id: \.element.rawValue) { index, pack in
                    if index > 0 { Hairline() }
                    SettingsRow(
                        title: pack.title,
                        subtitle: pack.buttonTitles.joined(separator: " · ")
                    ) {
                        ActionButton(tr("これにする", "Use this", "使用"), style: .secondary) {
                            model.applyPresetPack(pack)
                            dismiss()
                        }
                    }
                }
            }

            HStack {
                Spacer()
                ActionButton(tr("キャンセル", "Cancel", "取消"), style: .ghost) { dismiss() }
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Tokens.Window.canvas)
    }
}
