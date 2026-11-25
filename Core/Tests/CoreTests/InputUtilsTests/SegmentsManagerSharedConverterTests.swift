import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@MainActor
@Test func sharedConverterKeepsCompositionsIndependentAcrossDeactivation() {
    let converter = KanaKanjiConverter.withDefaultDictionary()
    func makeManager() -> SegmentsManager {
        SegmentsManager(
            kanaKanjiConverter: converter,
            applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            containerURL: nil,
            context: .init(useZenzai: false)
        )
    }
    let first = makeManager()
    var second: SegmentsManager? = makeManager()

    first.insertAtCursorPosition("ohayou", inputStyle: .roman2kana)
    second?.insertAtCursorPosition("arigat", inputStyle: .roman2kana)
    #expect(first.convertTarget == "おはよう")
    #expect(second?.convertTarget == "ありがt")

    first.deactivate(flushLearningData: false)
    second?.insertAtCursorPosition("ou", inputStyle: .roman2kana)
    #expect(second?.convertTarget == "ありがとう")

    second = nil
    first.activate()
    #expect(first.convertTarget == "おはよう")
    first.insertAtCursorPosition("nihongo", inputStyle: .roman2kana)
    first.deleteBackwardFromCursorPosition()
    first.insertAtCursorPosition("go", inputStyle: .roman2kana)
    #expect(first.convertTarget == "おはようにほんご")
    first.update(requestRichCandidates: false)
    if case .selecting(let candidates, _) = first.getCurrentCandidateWindow(inputState: .selecting) {
        #expect(!candidates.isEmpty)
    } else {
        Issue.record("Expected conversion candidates after reactivation")
    }
}

@MainActor
@Test func reactivationKeepsPendingRomanInput() {
    let manager = SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
    manager.insertAtCursorPosition("arigat", inputStyle: .roman2kana)
    let pendingText = manager.getCurrentMarkedText(inputState: .composing)
    manager.deactivate(flushLearningData: false)
    manager.activate()
    #expect(manager.getCurrentMarkedText(inputState: .composing) == pendingText)
    manager.insertAtCursorPosition("ou", inputStyle: .roman2kana)
    #expect(manager.convertTarget == "ありがとう")
}

@MainActor
@Test func reactivationKeepsSelectedCandidateAndCommitEndsComposition() throws {
    let manager = SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
    manager.insertAtCursorPosition("nihongo", inputStyle: .roman2kana)
    manager.update(requestRichCandidates: true)
    manager.requestSelectingRow(1)
    let selected = try #require(manager.selectedCandidate)
    let markedText = manager.getCurrentMarkedText(inputState: .selecting)
    manager.deactivate(flushLearningData: false)
    manager.activate()
    #expect(manager.selectedCandidate == selected)
    #expect(manager.getCurrentMarkedText(inputState: .selecting) == markedText)
    guard case .selecting = manager.getCurrentCandidateWindow(inputState: .selecting) else {
        Issue.record("Expected conversion candidates after reactivation")
        return
    }
    #expect(manager.commitMarkedText(inputState: .selecting) == markedText.map(\.content).joined())
    manager.deactivate(flushLearningData: false)
    manager.activate()
    #expect(manager.isEmpty)
}
