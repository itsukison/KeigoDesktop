import DesktopRewriteKit
import SwiftUI

struct ButtonPurposeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(alignment: .leading, spacing: 16) {
                Text(tr("ボタンを選ぶ", "Choose your buttons", "选择按钮"))
                    .font(Tokens.LightFont.body(32, weight: .semibold))
                Text(tr("よく使う指示をバーに並べましょう。次の画面で名前や指示、順番を調整できます。", "Start with the instructions you use most. You can edit their names, instructions and order next.", "将常用指令放到工具栏。下一步可以修改名称、指令和顺序。"))
                    .font(Tokens.LightFont.body(16)).foregroundStyle(Tokens.Window.textSecondary)
                Text(tr("変更はスマホにも同期されます。", "Changes sync to your phone too.", "修改也会同步到手机。"))
                    .font(Tokens.LightFont.body(13)).foregroundStyle(Tokens.Window.textSecondary)
            }.frame(width: 290, alignment: .leading)
            ScrollView {
                VStack(spacing: 12) {
                    if !coordinator.mainModel.prompts.isEmpty {
                        choice(tr("現在のボタンを使う", "Keep my current buttons", "保留现有按钮"),
                               detail: coordinator.mainModel.prompts.map(\.title).joined(separator: " · "),
                               selected: coordinator.usesCurrentButtons) { coordinator.selectCurrentButtons() }
                    }
                    ForEach(OnboardingPresetPack.available(for: coordinator.language), id: \.rawValue) { pack in
                        choice(pack.title, detail: pack.buttonTitles.joined(separator: " · "),
                               selected: coordinator.selectedPack == pack) { coordinator.select(pack: pack) }
                    }
                }.padding(2)
            }
        }.padding(24).foregroundStyle(Tokens.Window.textPrimary)
    }
    private func choice(_ title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Tokens.LightFont.body(16, weight: .medium))
                    Text(detail).font(Tokens.LightFont.body(13)).foregroundStyle(Tokens.Window.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Tokens.Window.accentText : Tokens.Window.textSecondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Tokens.Window.accentTint : Tokens.Window.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Tokens.Window.accent : Tokens.Window.hairline))
        }.buttonStyle(.plain)
    }
}

struct ButtonSetupReview: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(tr("自分のボタンに整える", "Make these buttons yours", "定制你的按钮"))
                .font(Tokens.LightFont.body(30, weight: .semibold))
            Text(tr("先頭がメインボタンです。名前、指示、順番を変更できます。", "The first button is your main button. Edit the names, instructions and order.", "第一个是主按钮。可修改名称、指令和顺序。"))
                .font(Tokens.LightFont.body(15)).foregroundStyle(Tokens.Window.textSecondary)
            HStack(alignment: .top, spacing: 24) {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(Array(coordinator.buttonDrafts.enumerated()), id: \.element.id) { index, draft in
                            HStack {
                                Button(draft.title) { selectedID = draft.id }
                                    .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                                Button { coordinator.moveDraft(id: draft.id, by: -1) } label: { Image(systemName: "chevron.up") }
                                    .disabled(index == 0).help(tr("上へ", "Move up", "上移"))
                                Button { coordinator.moveDraft(id: draft.id, by: 1) } label: { Image(systemName: "chevron.down") }
                                    .disabled(index == coordinator.buttonDrafts.count - 1).help(tr("下へ", "Move down", "下移"))
                            }.padding(14).background(selectedID == draft.id ? Tokens.Window.selectionLocal : Tokens.Window.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        ActionButton(tr("追加", "Add button", "添加按钮"), style: .secondary) {
                            coordinator.addDraft(); selectedID = coordinator.buttonDrafts.last?.id
                        }.disabled(coordinator.buttonDrafts.count >= 7)
                    }
                }.frame(width: 320)
                if let index = coordinator.buttonDrafts.firstIndex(where: { $0.id == selectedID }) {
                    draftEditor(index)
                }
            }
            if let error = coordinator.reviewError { Text(error).foregroundStyle(Tokens.Window.error) }
        }.padding(24)
            .onAppear { selectedID = coordinator.buttonDrafts.first?.id }
            .disabled(coordinator.isSavingButtons)
    }
    private func draftEditor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("名前", "Name", "名称")).font(Tokens.LightFont.body(13, weight: .medium))
            TextField("", text: binding(index, \.title)).textFieldStyle(.roundedBorder)
            Text(tr("AIへの指示", "Instructions", "AI指令")).font(Tokens.LightFont.body(13, weight: .medium))
            TextEditor(text: binding(index, \.prompt)).font(Tokens.LightFont.body(14))
                .scrollContentBackground(.hidden).padding(8).frame(minHeight: 180, maxHeight: 260)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tokens.Window.borderControl))
            Button(tr("このボタンを削除", "Remove this button", "移除此按钮"), role: .destructive) {
                coordinator.deleteDraft(id: coordinator.buttonDrafts[index].id)
                selectedID = coordinator.buttonDrafts.first?.id
            }.disabled(coordinator.buttonDrafts.count <= 1)
        }.padding(20).background(Tokens.Window.surface).clipShape(RoundedRectangle(cornerRadius: 14))
    }
    private func binding(_ index: Int, _ key: WritableKeyPath<OnboardingButtonDraft, String>) -> Binding<String> {
        let id = coordinator.buttonDrafts[index].id
        return Binding(get: { coordinator.buttonDrafts.first { $0.id == id }?[keyPath: key] ?? "" }, set: { value in
            guard var draft = coordinator.buttonDrafts.first(where: { $0.id == id }) else { return }
            draft[keyPath: key] = value; coordinator.updateDraft(draft)
        })
    }
}
