import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@Suite(.serialized)
struct PartialCandidateSubmissionTests {
    @MainActor
    private func manager() -> SegmentsManager {
        SegmentsManager(
            kanaKanjiConverter: .withDefaultDictionary(),
            applicationDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            containerURL: nil,
            context: .init(useZenzai: false)
        )
    }

    @MainActor
    @Test func canContinueTypingAfterConfirmingBeyondTheEditedRange() {
        let manager = self.manager()
        manager.insertAtCursorPosition("aiueo", inputStyle: .roman2kana)
        manager.editSegment(count: -3)
        let candidate = Candidate(text: "あいうえお", value: 0, composingCount: .surfaceCount(5), lastMid: 0, data: [])

        manager.prefixCandidateCommited(candidate, leftSideContext: "")
        #expect(manager.isEmpty)
        manager.insertAtCursorPosition(pieces: [.character("k"), .character("a")], inputStyle: .roman2kana)

        #expect(manager.convertTarget == "か")
    }

    @MainActor
    @Test func partialConfirmationPreservesTheSuffixAndItsCandidates() {
        let manager = self.manager()
        manager.insertAtCursorPosition("aiueo", inputStyle: .roman2kana)
        manager.editSegment(count: -4)
        let candidate = Candidate(text: "愛", value: 0, composingCount: .surfaceCount(2), lastMid: 0, data: [])

        manager.prefixCandidateCommited(candidate, leftSideContext: "")

        #expect(manager.convertTarget == "うえお")
        guard case let .selecting(candidates, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
            Issue.record("残りの候補が表示されていません。")
            return
        }
        #expect(!candidates.isEmpty)
        manager.insertAtCursorPosition(pieces: [.character("k"), .character("a")], inputStyle: .roman2kana)
        #expect(manager.convertTarget == "うえおか")
    }
}
