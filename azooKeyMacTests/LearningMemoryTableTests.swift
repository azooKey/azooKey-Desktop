import AppKit
@testable import Core
import SwiftUI
import XCTest

@testable import azooKeyMac

@MainActor
final class LearningMemoryTableTests: XCTestCase {
    func testSortingPreservesSelectedEntryAndColumnWidth() throws {
        let entries = ["候補A", "候補B"].map {
            LearningMemoryEditor.Entry(ruby: $0, word: $0, lcid: 1, rcid: 1, mid: 1, metadata: Data([0, 0, 0, 0, 3]), score: Data([0, 0, 0, 0]))
        }
        var selected = Set([entries[0].id])
        var order = [KeyPathComparator(\LearningMemoryEditor.Entry.lastUsedDay, order: .reverse)]
        var deletions = 0
        func view(_ rows: [LearningMemoryEditor.Entry]) -> LearningMemoryTable {
            LearningMemoryTable(entries: rows, selection: .init(get: { selected }, set: { selected = $0 }), sortOrder: .init(get: { order }, set: { order = $0 }), onDelete: { deletions += 1 })
        }
        let coordinator = view(entries).makeCoordinator()
        let table = LearningMemoryTable.TableView()
        let column = NSTableColumn(identifier: .init("word"))
        column.width = 300
        table.addTableColumn(column)
        table.delegate = coordinator
        table.dataSource = coordinator
        table.allowsMultipleSelection = true
        coordinator.updateTable(table)
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 0))

        table.sortDescriptors = [NSSortDescriptor(key: "word", ascending: false)]
        XCTAssertEqual(order, [KeyPathComparator(\LearningMemoryEditor.Entry.word, comparator: .localizedStandard, order: .reverse)])
        coordinator.parent = view(Array(entries.reversed()))
        coordinator.updateTable(table)
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 1))
        XCTAssertEqual(selected, [entries[0].id])
        XCTAssertEqual(column.width, 300)

        table.selectRowIndexes(IndexSet(integersIn: 0 ..< 2), byExtendingSelection: false)
        XCTAssertEqual(selected, Set(entries.map(\.id)))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51))
        table.keyDown(with: event)
        XCTAssertEqual(deletions, 1)
    }
}
