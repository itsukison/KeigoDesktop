import DesktopRewriteKit
import SwiftUI

private extension OnboardingPresetPack {
    var purposeArtwork: AsideBackdrop.Artwork {
        switch self {
        case .work: return .blue
        case .social: return .orange
        default: return .pink
        }
    }
}

struct ButtonPurposeStep: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var previewID: UUID?
    var initialPreviewIndex = 0

    private var preview: OnboardingButtonDraft? {
        coordinator.buttonDrafts.first { $0.id == previewID }
            ?? coordinator.buttonDrafts.dropFirst(initialPreviewIndex).first
            ?? coordinator.buttonDrafts.first
    }
    private var artwork: AsideBackdrop.Artwork { (coordinator.selectedPack ?? .starter).purposeArtwork }

    var body: some View {
        OnboardingSplitPage {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("どんな文章を書きますか？", "Choose your buttons", "选择你的按钮"))
                        .font(Tokens.LightFont.body(32, weight: .medium))
                    Text(tr("使い方に合うボタンのセットを選びましょう。\n名前と指示は次の画面で調整できます。", "Choose a set of four for the way you write.\nMake each button yours on the next screen.", "选择适合你的四按钮组合。\n下一步可以修改名称与指令。"))
                        .font(Tokens.LightFont.body(16))
                        .foregroundStyle(Tokens.Window.textSecondary)
                }
                if coordinator.isPreparingPurpose {
                    ProgressView().controlSize(.small)
                } else if let error = coordinator.purposeError ?? coordinator.mainModel.promptsError {
                    HStack {
                        Text(error).foregroundStyle(Tokens.Window.error)
                        Spacer()
                        Button(tr("再試行", "Retry", "重试")) { coordinator.retryPurpose() }
                    }.font(Tokens.LightFont.body(13))
                }
                ScrollView {
                    VStack(spacing: 10) {
                        if coordinator.canKeepCurrentButtons {
                            purposeChoice(title: tr("現在のボタンを使う", "Keep my current buttons", "保留现有按钮"),
                                caption: tr("保存済みの名前と指示を引き継ぎます", "Keep your saved names and instructions", "保留已保存的名称与指令"),
                                names: nil,
                                selected: coordinator.usesCurrentButtons, recommended: false) {
                                    coordinator.selectCurrentButtons(); previewID = nil
                                }
                        }
                        ForEach(OnboardingPresetPack.available(for: coordinator.language), id: \.self) { pack in
                            purposeChoice(title: pack.title, caption: pack.caption,
                                names: pack.drafts(writtenIn: coordinator.language).map(\.title).joined(separator: " · "),
                                selected: coordinator.selectedPack == pack,
                                recommended: pack == .starter) {
                                    coordinator.select(pack: pack); previewID = nil
                                }
                        }
                    }.padding(2)
                }
                .disabled(coordinator.isPreparingPurpose || coordinator.purposeError != nil || coordinator.mainModel.promptsError != nil)
            }
        } visual: {
            OnboardingVisualStage(artwork: artwork) {
                VStack(spacing: 20) {
                    VStack(spacing: 0) {
                        ZStack {
                            Text(preview?.title ?? tr("文章の例", "Writing example", "写作示例"))
                                .font(Tokens.LightFont.body(14, weight: .medium))
                                .lineLimit(1).padding(.horizontal, 66)
                            HStack(spacing: 6) {
                                ForEach(0..<3) { _ in
                                    Circle().fill(Color.black.opacity(0.14)).frame(width: 8, height: 8)
                                }
                                Spacer()
                            }.padding(.horizontal, 14).accessibilityHidden(true)
                        }.frame(height: 36)
                        ScrollView {
                            if let preview,
                               let example = OnboardingPresetPack.example(for: preview, writtenIn: coordinator.language) {
                                ButtonWritingExample(example: example, spacious: true)
                            } else if let preview {
                                Text(preview.prompt).font(Tokens.LightFont.body(16))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(height: 290).padding(24)
                    }
                    .background(Tokens.Window.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tokens.Window.hairline))
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
                    VStack(spacing: 12) {
                        ViewThatFits(in: .horizontal) {
                            previewBar.fixedSize()
                            ScrollView(.horizontal) { previewBar.fixedSize() }
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(tr("ボタンを選んで例を見る", "Select a button to see an example", "选择按钮，查看示例"))
                            .font(Tokens.LightFont.body(13)).foregroundStyle(Tokens.Window.textSecondary)
                    }
                }.padding(28)
            }
        }
        .foregroundStyle(Tokens.Window.textPrimary)
    }

    /// Local example selection only; decorative utilities never capture or take focus.
    private var previewBar: some View {
        HStack(spacing: 6) {
            BrandGlyph(size: 16, animation: .engaged, isAnimating: false)
                .accessibilityHidden(true)
            Rectangle().fill(Tokens.Overlay.hairline).frame(width: 1, height: 16)
            ForEach(coordinator.buttonDrafts) { draft in
                Button { previewID = draft.id } label: {
                    Text(draft.title).font(Tokens.Font.body(12, weight: .medium))
                        .lineLimit(1).padding(.horizontal, 10).frame(height: 24)
                        .background(Capsule().fill(preview?.id == draft.id ? Tokens.Overlay.hairline : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).help(draft.title)
                .accessibilityAddTraits(preview?.id == draft.id ? .isSelected : [])
            }
            Rectangle().fill(Tokens.Overlay.hairline).frame(width: 1, height: 16)
            Image(systemName: "pencil").font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24).accessibilityHidden(true)
        }
        .foregroundStyle(Tokens.Overlay.textPrimary)
        .padding(.horizontal, 12).frame(height: 34)
        .background(SmokedGlassSurface(shape: Capsule(), forceOpaque: true))
        .shadow(color: .black.opacity(0.20), radius: 10, y: 4)
    }

    private func purposeChoice(title: String, caption: String, names: String?,
                               selected: Bool, recommended: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19)).foregroundStyle(selected ? Tokens.Window.accentText : Tokens.Window.textSecondary).padding(.top, 2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title).font(Tokens.LightFont.body(16, weight: .medium))
                        Spacer(minLength: 2)
                        if recommended {
                            Text(tr("おすすめ", "Recommended", "推荐"))
                                .font(Tokens.LightFont.body(11, weight: .medium))
                                .foregroundStyle(Tokens.Window.textSecondary).padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Tokens.Window.selectionLocal).clipShape(Capsule())
                        }
                    }
                    Text(caption).font(Tokens.LightFont.body(13)).foregroundStyle(Tokens.Window.textSecondary)
                    if let names {
                        Text(names).font(Tokens.LightFont.body(13)).foregroundStyle(Tokens.Window.textSecondary)
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Window.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Tokens.Window.accentText : Tokens.Window.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ButtonSetupReview: View {
    @ObservedObject var coordinator: OnboardingCoordinator
    @State private var selectedID: UUID?

    private var selected: OnboardingButtonDraft? {
        coordinator.buttonDrafts.first { $0.id == selectedID } ?? coordinator.buttonDrafts.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("自分のボタンに整える", "Make these buttons yours", "定制你的按钮"))
                    .font(Tokens.LightFont.body(32, weight: .medium))
                Text(tr("ボタンを選んで、名前や書き方の指示を調整しましょう。", "Select a button to adjust its name and writing instructions.", "选择一个按钮，修改名称与写作指令。"))
                    .font(Tokens.LightFont.body(16)).foregroundStyle(Tokens.Window.textSecondary)
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(Array(coordinator.buttonDrafts.enumerated()), id: \.element.id) { index, draft in
                                    draftRow(draft, index: index)
                                }
                                Button {
                                    coordinator.addDraft()
                                    select(coordinator.buttonDrafts.last?.id)
                                } label: {
                                    Label(tr("ボタンを追加", "Add button", "添加按钮"), systemImage: "plus")
                                        .font(Tokens.LightFont.body(14, weight: .medium))
                                        .frame(maxWidth: .infinity, minHeight: 42)
                                        .background(Tokens.Window.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).disabled(coordinator.buttonDrafts.count >= 7)
                            }.padding(2)
                        }
                }
                .padding(12)
                .frame(width: 316)
                .frame(maxHeight: .infinity)
                .background(Tokens.Window.secondaryPanel)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                if let selected {
                    draftEditor(selected).id(selected.id)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        if coordinator.isPreparingPurpose {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(coordinator.purposeError ?? coordinator.mainModel.promptsError
                                 ?? tr("ボタンを選んで始めましょう。", "Choose buttons to get started.", "选择按钮以开始。"))
                                .font(Tokens.LightFont.body(16))
                            Button(tr("再試行", "Retry", "重试")) { coordinator.retryPurpose() }
                        }
                        Spacer()
                    }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .background(Tokens.Window.surface).clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }

        }
        .foregroundStyle(Tokens.Window.textPrimary)
        .onAppear { repairSelection() }
        .onChange(of: coordinator.buttonDrafts.map(\.id)) { _, _ in repairSelection() }
        .disabled(coordinator.isSavingButtons)
    }

    private func draftRow(_ draft: OnboardingButtonDraft, index: Int) -> some View {
        let isSelected = selected?.id == draft.id
        return Button { select(draft.id) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.title.isEmpty ? tr("名前なし", "Untitled", "未命名") : draft.title)
                        .font(Tokens.LightFont.body(16, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    if index == 0 {
                        Text(tr("メインボタン", "Main button", "主按钮"))
                            .font(Tokens.LightFont.body(12)).foregroundStyle(Tokens.Window.textSecondary)
                    }
                    if draft.isEnabled == false {
                        Text(tr("非表示", "Hidden from bar", "未显示在工具栏"))
                            .font(Tokens.LightFont.body(12)).foregroundStyle(Tokens.Window.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .modifier(SavedButtonRowSurface(selected: isSelected))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(tr("名前と指示を編集", "Edit name and instruction", "编辑名称与指令"))
    }

    private func draftEditor(_ draft: OnboardingButtonDraft) -> some View {
        let index = coordinator.buttonDrafts.firstIndex { $0.id == draft.id } ?? 0
        return VStack(spacing: 0) {
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(draft.title.isEmpty ? tr("名前なし", "Untitled", "未命名") : draft.title)
                    .font(Tokens.LightFont.body(20, weight: .medium))
                SavedButtonEditorFields(name: binding(draft.id, \.title),
                    instruction: binding(draft.id, \.prompt), onboarding: true)
                SavedButtonOrderControls(canMoveUp: index > 0,
                    canMoveDown: index < coordinator.buttonDrafts.count - 1,
                    moveUp: { coordinator.moveDraft(id: draft.id, by: -1) },
                    moveDown: { coordinator.moveDraft(id: draft.id, by: 1) })
                if let error = coordinator.reviewError ?? coordinator.purposeError ?? coordinator.mainModel.promptsError {
                    HStack {
                        Text(error).foregroundStyle(Tokens.Window.error)
                        Spacer()
                        if coordinator.purposeError != nil || coordinator.mainModel.promptsError != nil {
                            Button(tr("再試行", "Retry", "重试")) { coordinator.retryPurpose() }
                                .disabled(coordinator.isPreparingPurpose)
                        }
                    }.font(Tokens.LightFont.body(13))
                }
            }.padding(20)
            }
            HStack {
                Spacer()
                Button(role: .destructive) { delete(draft) } label: {
                    Label(tr("削除", "Delete", "删除"), systemImage: "trash")
                        .font(Tokens.LightFont.body(13))
                        .padding(.horizontal, 8).frame(height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(coordinator.buttonDrafts.count <= 1 ? Tokens.Window.textSecondary : Tokens.Window.error)
                .help(tr("このボタンを削除", "Delete this button", "删除此按钮"))
                .accessibilityLabel(tr("このボタンを削除", "Delete this button", "删除此按钮"))
                .disabled(coordinator.buttonDrafts.count <= 1)
            }.padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(Tokens.Window.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Tokens.Window.hairline))
    }

    private func delete(_ draft: OnboardingButtonDraft) {
        guard coordinator.buttonDrafts.count > 1,
              let index = coordinator.buttonDrafts.firstIndex(where: { $0.id == draft.id }) else { return }
        let adjacent = index + 1 < coordinator.buttonDrafts.count ? index + 1 : index - 1
        select(coordinator.buttonDrafts[adjacent].id)
        coordinator.deleteDraft(id: draft.id)
    }

    private func select(_ id: UUID?) {
        selectedID = id
    }

    private func repairSelection() {
        if !coordinator.buttonDrafts.contains(where: { $0.id == selectedID }) {
            select(coordinator.buttonDrafts.first?.id)
        }
    }

    private func binding(_ id: UUID, _ key: WritableKeyPath<OnboardingButtonDraft, String>) -> Binding<String> {
        Binding(get: { coordinator.buttonDrafts.first { $0.id == id }?[keyPath: key] ?? "" }, set: { value in
            guard var draft = coordinator.buttonDrafts.first(where: { $0.id == id }) else { return }
            draft[keyPath: key] = value
            coordinator.updateDraft(draft)
        })
    }
}

private struct ButtonWritingExample: View {
    let example: OnboardingButtonExample
    var spacious = false

    var body: some View {
        VStack(alignment: .leading, spacing: spacious ? 18 : 12) {
            Text(tr("例 · 実際の生成結果は変わります", "Example · results will vary", "示例 · 实际生成结果会有所不同"))
                .font(Tokens.LightFont.body(12)).foregroundStyle(Tokens.Window.textSecondary)
            let layout = spacious ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("元の文章", "Before", "原文")).font(Tokens.LightFont.body(12, weight: .medium))
                        .foregroundStyle(Tokens.Window.textSecondary)
                    Text(example.input).font(Tokens.LightFont.body(spacious ? 16 : 14)).lineSpacing(4)
                        .foregroundStyle(Tokens.Window.textSecondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("書き換えた文章", "After", "改写后")).font(Tokens.LightFont.body(12, weight: .medium))
                        .foregroundStyle(Tokens.Window.textSecondary)
                    Text(example.output).font(Tokens.LightFont.body(spacious ? 16 : 14)).lineSpacing(4)
                        .foregroundStyle(Tokens.Window.textPrimary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
