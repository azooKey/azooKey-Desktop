import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@MainActor
private func makeCursorTestManager() -> SegmentsManager {
    SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
}

@Test(arguments: [InputState.composing, .previewing])
func arrowsMoveTheCursorInUnconfirmedText(_ state: InputState) {
    for (keyCode, count) in [(UInt16(123), -1), (UInt16(124), 1)] {
        let event = KeyEventCore(modifierFlags: [], characters: nil, charactersIgnoringModifiers: nil, keyCode: keyCode)
        let (action, callback) = state.event(
            eventCore: event,
            userAction: UserAction.getUserAction(eventCore: event, inputLanguage: .japanese),
            inputLanguage: .japanese,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false
        )
        guard case .moveCursor(let actualCount) = action else {
            Issue.record("Expected a cursor movement, got \(action)")
            return
        }
        #expect(actualCount == count)
        switch (state, callback) {
        case (.composing, .fallthrough), (.previewing, .transition(.composing)):
            break
        default:
            Issue.record("Expected to continue composing, got \(callback)")
        }
    }
}

@Test(arguments: [InputState.none, .composing, .previewing, .selecting, .replaceSuggestion])
func forwardDeleteIsConsumedWhileEditingMarkedText(_ state: InputState) {
    let event = KeyEventCore(modifierFlags: [], characters: nil, charactersIgnoringModifiers: nil, keyCode: 0x75)
    let (action, callback) = state.event(
        eventCore: event,
        userAction: UserAction.getUserAction(eventCore: event, inputLanguage: .japanese),
        inputLanguage: .japanese,
        liveConversionEnabled: true,
        enableDebugWindow: false,
        enableSuggestion: false
    )
    switch (state, action, callback) {
    case (.none, .fallthrough, .fallthrough),
         (.composing, .consume, .fallthrough),
         (.previewing, .consume, .fallthrough),
         (.selecting, .consume, .fallthrough),
         (.replaceSuggestion, .consume, .fallthrough):
        break
    default:
        Issue.record("Unexpected Forward Delete behavior in \(state): \(action), \(callback)")
    }
}

@MainActor
@Test func composingCursorAllowsInsertionAndDeletionWithoutLosingTheSuffix() {
    let manager = makeCursorTestManager()
    manager.insertAtCursorPosition("aiueo", inputStyle: .roman2kana)
    manager.moveCursor(count: -3)
    let markedText = manager.getCurrentMarkedText(inputState: .composing)
    #expect(markedText.map(\.content).joined() == "あいうえお")
    #expect(markedText.selectionRange == NSRange(location: 2, length: 0))

    manager.insertAtCursorPosition("k", inputStyle: .roman2kana)
    #expect(manager.convertTarget == "あいkうえお")
    manager.insertAtCursorPosition("a", inputStyle: .roman2kana)
    #expect(manager.convertTarget == "あいかうえお")
    #expect(manager.getCurrentMarkedText(inputState: .composing).selectionRange == NSRange(location: 3, length: 0))
    manager.deleteBackwardFromCursorPosition()
    #expect(manager.convertTarget == "あいうえお")
    #expect(manager.getCurrentMarkedText(inputState: .composing).selectionRange == NSRange(location: 2, length: 0))
    #expect(manager.commitMarkedText(inputState: .composing) == "あいうえお")
    #expect(manager.isEmpty)
}

@MainActor
@Test func composingCursorSupportsCustomKanaInputAndStopsAtTextBoundaries() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tsv")
    try "a\tち\nt\tか\nk\tの\n".write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    let name = "composition-cursor-\(UUID().uuidString)"
    InputStyleManager.registerInputStyle(table: try InputStyleManager.loadTable(from: url), for: name)
    let style = InputStyle.mapped(id: .tableName(name))
    let manager = makeCursorTestManager()
    manager.insertAtCursorPosition("at", inputStyle: style)
    manager.moveCursor(count: -1)
    manager.insertAtCursorPosition("k", inputStyle: style)
    #expect(manager.convertTarget == "ちのか")
    manager.deleteBackwardFromCursorPosition()
    #expect(manager.convertTarget == "ちか")
    manager.moveCursor(count: -100)
    manager.deleteBackwardFromCursorPosition()
    #expect(manager.convertTarget == "ちか")
    #expect(manager.getCurrentMarkedText(inputState: .composing).selectionRange == NSRange(location: 0, length: 0))
    manager.moveCursor(count: 100)
    #expect(manager.getCurrentMarkedText(inputState: .composing).selectionRange == NSRange(location: 2, length: 0))
}

@MainActor
@Test func composingCursorUsesUTF16PositionsAndPreservesCombinedCharacters() {
    let manager = makeCursorTestManager()
    manager.insertAtCursorPosition("あ😀か\u{3099}う", inputStyle: .direct)
    manager.moveCursor(count: -1)
    #expect(manager.getCurrentMarkedText(inputState: .composing).selectionRange == NSRange(location: 5, length: 0))
    manager.moveCursor(count: -1)
    #expect(manager.getCurrentMarkedText(inputState: .composing).selectionRange == NSRange(location: 3, length: 0))
    manager.deleteBackwardFromCursorPosition()
    #expect(manager.convertTarget == "あか\u{3099}う")
    #expect(manager.getCurrentMarkedText(inputState: .composing).selectionRange == NSRange(location: 1, length: 0))
}

@MainActor
@Test func conversionAfterCursorEditingStartsWithTheWholeInput() {
    let manager = makeCursorTestManager()
    manager.insertAtCursorPosition("aiueo", inputStyle: .roman2kana)
    manager.moveCursor(count: -3)
    manager.insertCompositionSeparator(inputStyle: .roman2kana, skipUpdate: false)
    manager.moveCursor(count: -1)
    #expect(manager.convertTarget == "あいうえお")
    #expect(manager.getCurrentMarkedText(inputState: .composing).selectionRange == NSRange(location: 4, length: 0))
}

@MainActor
@Test func deletingWhileAdjustingASegmentStillDeletesFromTheEnd() {
    let manager = makeCursorTestManager()
    manager.insertAtCursorPosition("aiueo", inputStyle: .roman2kana)
    manager.editSegment(count: -2)
    manager.deleteBackwardFromCursorPosition()
    #expect(manager.convertTarget == "あいうえ")
}
