import AppKit
import DesktopRewriteKit
import SwiftUI

/// ボタン — the hover row, editable.
///
/// This writes to `user_prompts`, the one table both surfaces own read-write (§2).
/// All four owner-scoped RLS policies already exist on it, so nothing here needed a
/// migration; what it did need is the three-column care documented on
/// `UserPromptRemoteStore`'s write section.
struct ButtonsView: View {
    @ObservedObject var model: MainModel

    /// Rows are a fixed height so the drag can turn travel into an index with
    /// division rather than by measuring every row's frame.
    static let rowHeight: CGFloat = 60

    /// The gesture's raw translation, and the travel already spent on completed swaps.
    ///
    /// **These have to be two numbers.** The first version kept one and subtracted a
    /// row's height from it after each swap — but `DragGesture.translation` is measured
    /// from where the drag began, so the very next event overwrote the subtraction. The
    /// row snapped back to the pointer's raw travel, immediately crossed the threshold
    /// again, and the list flipped back and forth: the "jumping around" that made it
    /// impossible to place a button. The visible offset is `translation - consumed`,
    /// and only `consumed` is ever adjusted.
    @State private var draggingId: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var consumedTravel: CGFloat = 0
    @State private var pendingDelete: UserPrompt?

    private var dragOffset: CGFloat { dragTranslation - consumedTravel }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageTitle(
                title: "ボタン",
                subtitle: "バーに並ぶボタンです。スマホの敬語ボタンと同じものが表示されます。"
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
                list
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
            Text("\(model.prompts.filter(\.isEnabled).count) / \(model.prompts.count) 個を表示中・ドラッグで並べ替え")
                .font(Tokens.Font.body(13))
                .foregroundStyle(Tokens.Window.textTertiary)
            Spacer()
            ActionButton("ボタンを追加", icon: .add, style: .primary) {
                model.addPrompt()
            }
        }
    }

    @ViewBuilder
    private var list: some View {
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
            Card(padding: 0, spacing: 0) {
                VStack(spacing: 0) {
                    // Iterating the prompts directly rather than `enumerated()`: the tuple
                    // array changes every time the order does, which churned the row
                    // closures — including the drag gesture — on every swap.
                    ForEach(model.prompts) { prompt in
                        if model.editingPromptId == prompt.id {
                            PromptEditor(
                                prompt: prompt,
                                canDelete: model.canDelete(prompt),
                                onSave: { model.save($0); model.editingPromptId = nil },
                                onDelete: {
                                    model.editingPromptId = nil
                                    pendingDelete = prompt
                                },
                                onCancel: { model.editingPromptId = nil }
                            )
                            .id(prompt.id)
                        } else {
                            row(prompt)
                        }
                    }
                }
            }
            // Rows that are not the one under the pointer slide to their new place
            // instead of teleporting, which is what makes the reorder legible. The
            // dragged row opts out — see `row(_:)`.
            .animation(.easeOut(duration: 0.16), value: model.prompts.map(\.id))
        }
    }

    private func row(_ prompt: UserPrompt) -> some View {
        let isDragging = draggingId == prompt.id
        return PromptRow(
            prompt: prompt,
            isDragging: isDragging,
            isReordering: draggingId != nil,
            showsSeparator: prompt.id != model.prompts.last?.id && !isDragging,
            canDelete: model.canDelete(prompt),
            onToggle: { model.setEnabled(prompt, $0) },
            onEdit: { model.editingPromptId = prompt.id },
            onDelete: { pendingDelete = prompt },
            dragGesture: dragGesture(for: prompt)
        )
        .frame(height: Self.rowHeight)
        .offset(y: isDragging ? dragOffset : 0)
        .zIndex(isDragging ? 1 : 0)
        // **The fix for the shaking.** A swap moves this row ±rowHeight in layout and
        // changes its offset by ∓rowHeight to compensate. Under the container's
        // animation both of those ease over 0.16 s and cancel — until the next
        // `onChanged` lands a few milliseconds later and writes the offset in an
        // *un*-animated transaction. The offset then snaps to its final value while
        // the layout half is still 160 ms from arriving, so the row swings a full row
        // height and eases back. Every swap.
        //
        // The row under the pointer must be positionally exact at all times, so it
        // takes no animation at all and both halves land in the same frame.
        .transaction { transaction in
            if isDragging { transaction.animation = nil }
        }
    }

    /// Live reorder. The row under the pointer is swapped once the drag has travelled
    /// a row's height; that height goes into `consumedTravel`, which keeps the row
    /// sitting under the cursor while the list rearranges beneath it. Committing
    /// happens once, on release — see `MainModel.commitOrder`.
    ///
    /// Swapping on `.rounded()` of a *half*-row would flip at the moment two rows only
    /// half overlap, which reads as twitchy; a full row of travel is the point at which
    /// the two rows have actually exchanged places.
    private func dragGesture(for prompt: UserPrompt) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if draggingId != prompt.id {
                    draggingId = prompt.id
                    dragTranslation = 0
                    consumedTravel = 0
                    // An open editor is a different height, which would break the
                    // fixed-row arithmetic this depends on.
                    model.editingPromptId = nil
                    NSCursor.closedHand.push()
                }
                // Computed locally and written back once. The previous version read
                // `dragOffset` — derived from `@State` — while mutating the `@State` it
                // derives from, inside the loop condition. Plain arithmetic here means
                // the swap count cannot depend on when SwiftUI makes a write visible.
                let translation = value.translation.height
                var consumed = consumedTravel

                // Re-measured each pass rather than jumping `steps` rows at once: a
                // fast flick must not carry past a slot boundary the swap is not
                // allowed to cross.
                while abs(translation - consumed) >= Self.rowHeight {
                    let direction = (translation - consumed) > 0 ? 1 : -1
                    guard model.moveLocally(prompt, by: direction) else { break }
                    consumed += CGFloat(direction) * Self.rowHeight
                }

                dragTranslation = translation
                consumedTravel = consumed
            }
            .onEnded { _ in
                guard draggingId == prompt.id else { return }
                // Exactly one pop for the one push above.
                NSCursor.pop()
                draggingId = nil
                dragTranslation = 0
                consumedTravel = 0
                model.commitOrder()
            }
    }
}

private struct PromptRow<G: Gesture>: View {
    let prompt: UserPrompt
    let isDragging: Bool
    /// True for *every* row while any row is being dragged.
    ///
    /// A reorder slides rows under a stationary pointer, so each one crossing it fires
    /// `onHover` twice. Left alone, the grips and icon buttons flash on and off down
    /// the whole list while the drag is in progress.
    let isReordering: Bool
    let showsSeparator: Bool
    let canDelete: Bool
    /// `Binding`'s setter is `@Sendable` as of the macOS 26 SDK, so the callback it
    /// wraps has to declare the isolation it actually runs on.
    let onToggle: @MainActor @Sendable (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let dragGesture: G

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            GripHandle(active: isDragging || hovering)
                .cursor(.openHand)
                .gesture(dragGesture)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(prompt.title)
                        .font(Tokens.Font.body(14, weight: .medium))
                        .foregroundStyle(Tokens.Window.textPrimary)
                    // The phone's primary toolbar slot. Shown because it is why this
                    // row cannot be dragged past the ones below it.
                    if prompt.slot == .main {
                        Badge("メイン")
                    }
                }
                Text(prompt.prompt.isEmpty ? "指示が未入力です" : prompt.prompt)
                    .font(Tokens.Font.body(13))
                    .foregroundStyle(Tokens.Window.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(get: { prompt.isEnabled }, set: onToggle))
                .accentSwitch()
                .labelsHidden()

            IconButton(icon: .edit, help: "編集", action: onEdit)
            // Visible on the row, not buried in the editor. `canDelete` is false for
            // seeded buttons — the phone re-seeds them from `builtin_key`, so a delete
            // would come back on the next sync.
            IconButton(
                icon: .trash,
                help: canDelete ? "削除" : "最初から入っているボタンは削除できません",
                enabled: canDelete,
                action: onDelete
            )
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Tokens.Window.smallCardRadius, style: .continuous)
                .fill(isDragging ? Tokens.Window.canvas : (hovering ? Tokens.Window.surface : .clear))
                .shadow(
                    color: isDragging ? .black.opacity(0.12) : .clear,
                    radius: 10,
                    y: 3
                )
        )
        .overlay(alignment: .bottom) {
            if showsSeparator { Hairline() }
        }
        .opacity(prompt.isEnabled ? 1 : 0.55)
        .onHover { inside in
            guard !isReordering else { return }
            hovering = inside
        }
        // Exits were swallowed for the duration of the drag, so a row that was hovered
        // when it started would stay lit afterwards even though the pointer had long
        // since left it. Cleared on release; the next mouse move re-lights whichever
        // row is genuinely under the cursor.
        .onChange(of: isReordering) { _, reordering in
            if !reordering { hovering = false }
        }
    }
}

/// Inline rather than a sheet: the prompt text is the thing being compared against
/// its neighbours, and a modal hides exactly that.
private struct PromptEditor: View {
    let prompt: UserPrompt
    let canDelete: Bool
    let onSave: (UserPrompt) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var text: String

    init(
        prompt: UserPrompt,
        canDelete: Bool,
        onSave: @escaping (UserPrompt) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.prompt = prompt
        self.canDelete = canDelete
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
                if canDelete {
                    ActionButton("削除", style: .secondary, action: onDelete)
                } else {
                    Text("最初から入っているボタンは削除できません。")
                        .font(Tokens.Font.body(12))
                        .foregroundStyle(Tokens.Window.textTertiary)
                }
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
        // The editor sits on the card's own white, not on a second surface: its two
        // fields are already `#f7f7f8` fills, and a grey panel behind grey fields is
        // one container too many.
        .padding(16)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
