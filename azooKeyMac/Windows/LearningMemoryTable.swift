import AppKit
import Core
import SwiftUI

// 大量の行を並べ替える際の差分計算を避け、表示中のセルだけを更新する。
struct LearningMemoryTable: NSViewRepresentable {
    let entries: [LearningMemoryEditor.Entry]
    @Binding var selection: Set<LearningMemoryEditor.Entry.ID>
    @Binding var sortOrder: [KeyPathComparator<LearningMemoryEditor.Entry>]
    let onDelete: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = TableView()
        table.delegate = context.coordinator
        table.dataSource = context.coordinator
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        for (key, title) in [("ruby", "読み"), ("word", "表記"), ("count", "回数"), ("lastUsedDay", "最終使用日")] {
            let column = NSTableColumn(identifier: .init(key))
            column.title = title
            column.sortDescriptorPrototype = NSSortDescriptor(key: key, ascending: true)
            column.width = key == "count" ? 50 : key == "lastUsedDay" ? 100 : 200
            column.minWidth = key == "ruby" || key == "word" ? 80 : column.width
            table.addTableColumn(column)
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let table = scroll.documentView as? TableView {
            context.coordinator.updateTable(table)
        }
    }

    final class TableView: NSTableView {
        var onDelete: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 || event.keyCode == 117, !selectedRowIndexes.isEmpty {
                onDelete?()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private static let comparators: [String: KeyPathComparator<LearningMemoryEditor.Entry>] = [
            "ruby": .init(\.ruby, comparator: .localizedStandard),
            "word": .init(\.word, comparator: .localizedStandard),
            "count": .init(\.count),
            "lastUsedDay": .init(\.lastUsedDay)
        ]

        var parent: LearningMemoryTable
        private var entries: [LearningMemoryEditor.Entry] = []
        private var updating = false

        init(_ parent: LearningMemoryTable) { self.parent = parent }

        func updateTable(_ table: TableView) {
            updating = true
            defer { updating = false }
            table.onDelete = parent.onDelete
            let descriptors = parent.sortOrder.compactMap { comparator -> NSSortDescriptor? in
                guard let key = Self.comparators.first(where: { $0.value.keyPath == comparator.keyPath })?.key else {
                    return nil
                }
                return NSSortDescriptor(key: key, ascending: comparator.order == .forward)
            }
            if table.sortDescriptors != descriptors {
                table.sortDescriptors = descriptors
            }
            if entries != parent.entries {
                entries = parent.entries
                table.reloadData()
            }
            let selectedRows = IndexSet(entries.indices.filter { parent.selection.contains(entries[$0].id) })
            if table.selectedRowIndexes != selectedRows {
                table.selectRowIndexes(selectedRows, byExtendingSelection: false)
            }
        }

        func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let column = tableColumn, entries.indices.contains(row) else {
                return nil
            }
            let entry = entries[row]
            let text: String
            switch column.identifier.rawValue {
            case "ruby": text = entry.ruby
            case "word": text = entry.word
            case "count": text = String(entry.count)
            case "lastUsedDay": text = entry.lastUsedDate.formatted(.dateTime.year().month().day())
            default: return nil
            }
            let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTextField ?? NSTextField(labelWithString: "")
            cell.identifier = column.identifier
            cell.lineBreakMode = .byTruncatingTail
            cell.stringValue = text
            return cell
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !updating else {
                return
            }
            parent.sortOrder = tableView.sortDescriptors.compactMap { descriptor in
                guard var comparator = Self.comparators[descriptor.key ?? ""] else {
                    return nil
                }
                comparator.order = descriptor.ascending ? .forward : .reverse
                return comparator
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !updating, let table = notification.object as? NSTableView else {
                return
            }
            parent.selection = Set(table.selectedRowIndexes.compactMap { entries.indices.contains($0) ? entries[$0].id : nil })
        }
    }
}
