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
    first.insertAtCursorPosition("nihongo", inputStyle: .roman2kana)
    first.deleteBackwardFromCursorPosition()
    first.insertAtCursorPosition("go", inputStyle: .roman2kana)
    #expect(first.convertTarget == "にほんご")
    first.update(requestRichCandidates: false)
    if case .selecting(let candidates, _) = first.getCurrentCandidateWindow(inputState: .selecting) {
        #expect(!candidates.isEmpty)
    } else {
        Issue.record("Expected conversion candidates after reactivation")
    }
}
