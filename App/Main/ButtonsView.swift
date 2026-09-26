import DesktopRewriteKit
import SwiftUI

struct ButtonsView: View {
    @ObservedObject var model: MainModel
    @State private var selected: UserPrompt?
    @State private var adding = false
    @State private var title = ""
    @State private var instruction = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showDiscard = false
    @State private var pendingDelete: UserPrompt?
    @State private var choosingPack = false

    private var dirty: Bool {
        title != (selected?.title ?? "") || instruction != (selected?.prompt ?? "")
    }
    private var valid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageTitle(title: tr("ボタン", "Buttons", "按钮"), subtitle: tr(
                "Macで使う指示を、自分の順番で。",
                "Your Mac buttons, in your order.",
                "Mac常用指令，按你的顺序排列。"))
            if model.isSignedIn {
                toolbar
                if let error = model.promptsError {
                    HStack {
                        Text(error).foregroundStyle(Tokens.Window.error)
                        Spacer()
                        Button(tr("再試行", "Retry", "重试")) { Task { await model.reloadPrompts() } }
                    }.font(Tokens.LightFont.body(13))
                }
                if model.buttonsWriteOtherLanguage {
                    HStack {
                        Text(tr("ボタンの言語が設定と異なります。", "Your presets use a different writing language.", "预设按钮的写作语言与设置不同。"))
                        Spacer()
                        Button(tr("セットを選ぶ", "Choose a set", "选择按钮组")) {
                            confirmChange { choosingPack = true }
                        }
                    }.font(Tokens.LightFont.body(13)).padding(14).background(Tokens.Window.accentTint)
                }
                HStack(alignment: .top, spacing: 20) {
                    buttonList.frame(width: 228)
                    editor.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(tr("サインインするとボタンを編集できます。", "Sign in to edit your buttons.", "登录后即可编辑按钮。"))
                ActionButton(tr("サインイン", "Sign in", "登录")) { model.page = .account }
            }
        }
        .onAppear {
            synchronizeSelection()
            model.confirmLeavingButtons = { action in confirmChange(action) }
        }
        .onDisappear { model.confirmLeavingButtons = nil }
        .onChange(of: model.prompts) { _, _ in if !dirty { synchronizeSelection() } }
        .onChange(of: model.signedInEmail) { _, _ in
            selected = nil; adding = false; title = ""; instruction = ""
            pendingAction = nil; showDiscard = false
        }
        .alert(tr("変更を破棄しますか？", "Discard unsaved changes?", "放弃未保存的修改？"), isPresented: $showDiscard) {
            Button(tr("編集を続ける", "Keep editing", "继续编辑"), role: .cancel) { pendingAction = nil }
            Button(tr("破棄", "Discard", "放弃"), role: .destructive) {
                let action = pendingAction; pendingAction = nil
                load(selected); action?()
            }
        }
        .alert(item: $pendingDelete) { prompt in
            Alert(title: Text(tr("このボタンを削除しますか？", "Delete this button?", "删除此按钮？")),
                  message: Text(tr("Mac用のボタンから削除されます。元に戻せません。", "This deletes the desktop button. This cannot be undone.", "将删除此桌面按钮，且无法撤销。")),
                  primaryButton: .destructive(Text(tr("削除", "Delete", "删除"))) { model.delete(prompt) },
                  secondaryButton: .cancel())
        }
        .sheet(isPresented: $choosingPack) { PresetPackPicker(model: model) { choosingPack = false } }
    }

    private var toolbar: some View {
        HStack {
            Text(tr("\(model.prompts.filter(\.isEnabled).count)個をバーに表示中",
                    "\(model.prompts.filter(\.isEnabled).count) shown on the bar",
                    "工具栏上显示\(model.prompts.filter(\.isEnabled).count)个"))
                .font(Tokens.LightFont.body(13)).foregroundStyle(Tokens.Window.textSecondary)
            if model.isLoadingPrompts || model.isSavingButtons || model.isReorderingButtons { ProgressView().controlSize(.small) }
            Spacer()
            ActionButton(tr("ボタンを追加", "Add a button", "添加按钮"), icon: .add, style: .secondary) {
                confirmChange { selected = nil; adding = true; title = ""; instruction = "" }
            }.disabled(model.isSavingButtons)
        }
    }

    private var buttonList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("表示順", "Bar order", "显示顺序"))
                .font(Tokens.LightFont.body(13, weight: .medium)).foregroundStyle(Tokens.Window.textSecondary)
                .padding(.horizontal, 12)
            if model.prompts.isEmpty {
                Text(model.isLoadingPrompts ? tr("読み込み中…", "Loading…", "正在加载…") : tr("まだボタンがありません。", "No buttons yet.", "还没有按钮。"))
                    .font(Tokens.LightFont.body(14)).padding(16)
            }
            if !model.prompts.isEmpty {
                SavedButtonReorderList(prompts: model.prompts,
                    selectedID: adding ? nil : selected?.id,
                    enabled: !model.isSavingButtons && !model.isLoadingPrompts,
                    onSelect: { prompt in confirmChange { load(prompt) } },
                    onMove: { id, insertionIndex in
                        model.movePrompt(id: id, toInsertionIndex: insertionIndex)
                    })
                    .padding(.horizontal, 6)
            }

        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Window.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var editor: some View {
        if selected != nil || adding {
            VStack(alignment: .leading, spacing: 24) {
                Text(adding ? tr("新しいボタン", "New button", "新按钮") : (selected?.title ?? ""))
                    .font(Tokens.LightFont.body(16, weight: .medium))
                SavedButtonEditorFields(name: $title, instruction: $instruction)
                    .id(adding ? "new" : selected?.id.uuidString ?? "none")
                if let current = model.prompts.first(where: { $0.id == selected?.id }),
                   let index = model.prompts.firstIndex(where: { $0.id == current.id }) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            visibilityControl(current)
                            Spacer(minLength: 0)
                            orderControls(current, index: index)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            visibilityControl(current)
                            orderControls(current, index: index)
                        }
                    }

                }
                HStack {
                    if let selected {
                        Button(role: .destructive) { confirmChange { pendingDelete = selected } } label: {
                            Label(tr("削除", "Delete", "删除"), systemImage: "trash")
                                .padding(.vertical, 8).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .font(Tokens.LightFont.body(13))
                        .foregroundStyle(Tokens.Window.error)
                        .disabled(model.isReorderingButtons)
                    }
                    Spacer()
                    ActionButton(tr("キャンセル", "Cancel", "取消"), style: .ghost) { load(selected) }
                    ActionButton(tr("保存", "Save", "保存")) {
                        let current = selected; let name = title; let text = instruction
                        Task {
                            if await model.saveButton(current, title: name, instruction: text) {
                                load(model.prompts.first { $0.id == model.editingPromptId })
                            }
                        }
                    }.disabled(!valid || !dirty || model.isSavingButtons || model.isReorderingButtons)
                }
            }.padding(20).background(Tokens.Window.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Tokens.Window.hairline))
                .disabled(model.isSavingButtons)
        } else {
            Text(tr("ボタンを選択するか、新しく追加してください。", "Select a button or add a new one.", "选择按钮或添加新按钮。"))
                .font(Tokens.LightFont.body(14)).foregroundStyle(Tokens.Window.textSecondary).padding(24)
        }
    }

    private func visibilityControl(_ prompt: UserPrompt) -> some View {
        Toggle(tr("バーに表示", "Show on bar", "在工具栏显示"), isOn: Binding(
            get: { model.prompts.first { $0.id == prompt.id }?.isEnabled ?? false },
            set: { model.setEnabled(prompt, $0) }))
            .toggleStyle(.switch).controlSize(.small)
            .font(Tokens.LightFont.body(13))
            .fixedSize()
            .disabled(model.isReorderingButtons)
    }

    private func orderControls(_ prompt: UserPrompt, index: Int) -> some View {
        SavedButtonOrderControls(canMoveUp: index > 0,
            canMoveDown: index < model.prompts.count - 1,
            moveUp: { _ = model.movePrompt(id: prompt.id, by: -1) },
            moveDown: { _ = model.movePrompt(id: prompt.id, by: 1) })
            .fixedSize()
    }

    private func confirmChange(_ action: @escaping () -> Void) {
        guard !model.isSavingButtons else { return }
        if dirty { pendingAction = action; showDiscard = true } else { action() }
    }
    private func load(_ prompt: UserPrompt?) {
        selected = prompt; adding = false; title = prompt?.title ?? ""; instruction = prompt?.prompt ?? ""
    }
    private func synchronizeSelection() {
        if adding { return }
        load(model.prompts.first { $0.id == selected?.id } ?? model.prompts.first)
    }
}

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
