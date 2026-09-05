import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@MainActor
struct SegmentsManagerPostalAddressTests {
    private func withManager(_ body: (SegmentsManager) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = SegmentsManager(kanaKanjiConverter: .withDefaultDictionary(), applicationDirectoryURL: directory, containerURL: nil, context: .init(useZenzai: false))
        try body(manager)
    }

    @Test(arguments: ["2400054", "240-0054", "240ｰ0054", "240ー0054", "２４０－００５４"])
    func addressCanBeSelectedWithoutLosingOriginal(input: String) throws {
        try withManager { manager in
            manager.insertAtCursorPosition(input, inputStyle: .direct)
            try checkAndCommit(manager)
        }
    }

    @Test func physicalHyphenInJapaneseModeWorks() throws {
        try withManager { manager in
            for character in "240-0054" {
                let code: UInt16 = character == "-" ? 27 : ["2": 19, "4": 21, "0": 29, "5": 23][character]!
                let action = UserAction.getUserAction(eventCore: .init(modifierFlags: [], characters: String(character), charactersIgnoringModifiers: String(character), keyCode: code), inputLanguage: .japanese)
                switch action {
                case .number(let number): manager.insertAtCursorPosition(pieces: [number.inputPiece], inputStyle: .roman2kana)
                case .input(let pieces): manager.insertAtCursorPosition(pieces: pieces, inputStyle: .roman2kana)
                default: Issue.record("Unexpected postal input action")
                }
            }
            try checkAndCommit(manager)
        }
    }

    @Test func editedSegmentDoesNotOfferWholePostalAddress() throws {
        try withManager { manager in
            manager.insertAtCursorPosition("2400054", inputStyle: .direct)
            manager.editSegment(count: -1)
            manager.update(requestRichCandidates: true)
            manager.requestSetCandidateWindowState(visible: true)
            guard case .selecting(let choices, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
                Issue.record("Expected edited-segment candidates")
                return
            }
            #expect(!choices.contains { $0.text == "神奈川県横浜市保土ケ谷区西谷" })
            #expect(manager.convertTarget == "2400054")
            manager.editSegment(count: 1)
            try checkAndCommit(manager)
        }
    }

    private func checkAndCommit(_ manager: SegmentsManager) throws {
        let original = manager.convertTarget
        for rich in [false, true] {
            manager.update(requestRichCandidates: rich)
            manager.requestSetCandidateWindowState(visible: true)
            guard case .selecting(let choices, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
                Issue.record("Expected postal address candidates")
                return
            }
            let matches = choices.filter { $0.text == "神奈川県横浜市保土ケ谷区西谷" }
            #expect(matches.count == 1)
            #expect(choices.contains { $0.text == original })
            #expect(manager.convertTarget == original)
            if rich {
                let candidate = try #require(matches.first)
                #expect(!candidate.isLearningTarget)
                manager.prefixCandidateCommited(candidate, leftSideContext: "")
                #expect(manager.isEmpty)
            }
        }
    }
}
