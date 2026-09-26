import AppKit
import DesktopRewriteKit
import SwiftUI

struct SavedButtonReorderList: View {
    let prompts: [UserPrompt]
    let selectedID: UUID?
    let enabled: Bool
    let onSelect: (UserPrompt) -> Void
    let onMove: (UUID, Int) -> Bool

    var body: some View {
        GeometryReader { geometry in
            NativeButtonReorderList(prompts: prompts, selectedID: selectedID, enabled: enabled,
                onSelect: onSelect, onMove: onMove)
                .frame(height: height(width: geometry.size.width))
        }
        .frame(height: height(width: 216))
    }

    private func height(width: CGFloat) -> CGFloat {
        min(420, prompts.enumerated().reduce(CGFloat(0)) { total, item in
            total + NativeButtonReorderList.rowHeight(item.element, index: item.offset, width: width) + 8
        })
    }
}

private struct NativeButtonReorderList: NSViewRepresentable {
    let prompts: [UserPrompt]
    let selectedID: UUID?
    let enabled: Bool
    let onSelect: (UserPrompt) -> Void
    let onMove: (UUID, Int) -> Bool
    private static let pasteboardType = NSPasteboard.PasteboardType("com.core7.keigobutton.desktop-button-order")

    static func rowHeight(_ prompt: UserPrompt, index: Int, width: CGFloat) -> CGFloat {
        let titleHeight = (prompt.title as NSString).boundingRect(
            with: NSSize(width: max(40, width - 58), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)]).height
        let metadataCount = (index == 0 ? 1 : 0) + (prompt.isEnabled ? 0 : 1)
        return max(52, ceil(titleHeight) + CGFloat(metadataCount * 19) + 20)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = ReorderTableView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("button"))
        column.resizingMask = .autoresizingMask
        column.width = 216
        table.addTableColumn(column)
        table.frame = NSRect(x: 0, y: 0, width: 216, height: 0)
        table.autoresizingMask = [.width]
        table.style = .plain
        table.headerView = nil
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 8)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.registerForDraggedTypes([Self.pasteboardType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.setDraggingSourceOperationMask([], forLocal: false)
        table.setAccessibilityLabel(tr("ボタンの表示順", "Button order", "按钮显示顺序"))
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        scroll.autohidesScrollers = true
        scroll.documentView = table
        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let changed = coordinator.parent.prompts != prompts || coordinator.parent.selectedID != selectedID
            || coordinator.parent.enabled != enabled
        coordinator.parent = self
        guard let table = coordinator.table else { return }
        table.dragEnabled = enabled
        if changed || table.numberOfRows != prompts.count {
            table.reloadData()
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<prompts.count))
        }
        let selection = prompts.firstIndex { $0.id == selectedID }
        table.selectRowIndexes(selection.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
        table.window?.invalidateCursorRects(for: table)
    }

    @MainActor final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: NativeButtonReorderList
        weak var table: ReorderTableView?
        private var draggedID: UUID?
        private var sourceOrder: [UUID] = []

        init(_ parent: NativeButtonReorderList) { self.parent = parent }
        func numberOfRows(in tableView: NSTableView) -> Int { parent.prompts.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            NativeButtonReorderList.rowHeight(parent.prompts[row], index: row, width: tableView.bounds.width)
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let prompt = parent.prompts[row]
            let host = PassiveButtonRow(rootView: ButtonReorderRow(prompt: prompt, isMain: row == 0,
                selected: parent.selectedID == prompt.id, enabled: parent.enabled))
            host.sizingOptions = []
            return host
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard parent.enabled, parent.prompts.indices.contains(row) else { return false }
            if table?.handlePressed == true { return true }
            parent.onSelect(parent.prompts[row])
            return false
        }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard parent.enabled, table?.handlePressed == true, parent.prompts.indices.contains(row) else { return nil }
            let item = NSPasteboardItem()
            item.setString(parent.prompts[row].id.uuidString, forType: NativeButtonReorderList.pasteboardType)
            draggedID = parent.prompts[row].id
            sourceOrder = parent.prompts.map(\.id)
            return item
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            session.animatesToStartingPositionsOnCancelOrFail = true
            NSCursor.closedHand.set()
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                       proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
            guard validSource(info), (0...parent.prompts.count).contains(row) else { return [] }
            tableView.setDropRow(row, dropOperation: .above)
            return .move
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                       row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard validSource(info), let draggedID, (0...parent.prompts.count).contains(row) else { return false }
            guard UserPromptOrder.moving(parent.prompts, id: draggedID, toInsertionIndex: row) != nil else { return true }
            return parent.onMove(draggedID, row)
        }

        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession,
                       endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            draggedID = nil
            sourceOrder = []
            table?.handlePressed = false
            let selectedRow = parent.prompts.firstIndex { $0.id == parent.selectedID }
            tableView.selectRowIndexes(selectedRow.map { IndexSet(integer: $0) } ?? [], byExtendingSelection: false)
            NSCursor.arrow.set()
            tableView.window?.invalidateCursorRects(for: tableView)
        }

        private func validSource(_ info: NSDraggingInfo) -> Bool {
            parent.enabled && (info.draggingSource as? NSTableView) === table
                && sourceOrder == parent.prompts.map(\.id)
                && info.draggingPasteboard.string(forType: NativeButtonReorderList.pasteboardType) == draggedID?.uuidString
        }
    }
}

private final class ReorderTableView: NSTableView {
    var handlePressed = false
    var dragEnabled = true

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        handlePressed = dragEnabled && point.x < 38 && row(at: point) >= 0
        super.mouseDown(with: event)
        handlePressed = false
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard dragEnabled else { return }
        let visibleRows = rows(in: visibleRect)
        guard visibleRows.location != NSNotFound else { return }
        for row in visibleRows.location..<(visibleRows.location + visibleRows.length) {
            let frame = rect(ofRow: row)
            addCursorRect(NSRect(x: 0, y: frame.minY, width: 38, height: frame.height), cursor: .openHand)
        }
    }
}

private final class PassiveButtonRow: NSHostingView<ButtonReorderRow> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct ButtonReorderRow: View {
    let prompt: UserPrompt
    let isMain: Bool
    let selected: Bool
    let enabled: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 3) {
                        Circle().frame(width: 3, height: 3)
                        Circle().frame(width: 3, height: 3)
                    }
                }
            }
            .foregroundStyle(Tokens.Window.textSecondary)
            .frame(width: 20, height: 28)
            .accessibilityLabel(tr("ドラッグして並べ替え", "Drag to reorder", "拖动排序"))
            VStack(alignment: .leading, spacing: 4) {
                Text(prompt.title).font(Tokens.LightFont.body(14, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if isMain {
                    Text(tr("メインボタン", "Main button", "主按钮"))
                        .font(Tokens.LightFont.body(12)).foregroundStyle(Tokens.Window.textSecondary)
                }
                if !prompt.isEnabled {
                    Text(tr("非表示", "Hidden from bar", "未显示在工具栏"))
                        .font(Tokens.LightFont.body(12)).foregroundStyle(Tokens.Window.textSecondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Tokens.Window.textPrimary)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .modifier(SavedButtonRowSurface(selected: selected))
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
