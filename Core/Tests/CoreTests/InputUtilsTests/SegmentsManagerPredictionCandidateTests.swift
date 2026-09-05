@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

private func makeCandidate(text: String, reading: String) -> Candidate {
    Candidate(
        text: text,
        value: 0,
        composingCount: .inputCount(reading.count),
        lastMid: MIDData.一般.mid,
        data: [.init(word: text, ruby: reading.toKatakana(), cid: CIDData.一般名詞.cid, mid: MIDData.一般.mid, value: 0)]
    )
}

private func makePredictionSegmentsManager() -> SegmentsManager {
    SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
}

@Test func testMakePredictionCandidateDeletesTrailingASCIIUsedForMatching() async throws {
    let source = makeCandidate(text: "おはようございます", reading: "おはようございます")
    let candidate = SegmentsManager.makePredictionCandidate(
        currentTarget: "おはようございm",
        candidate: source
    )

    #expect(candidate?.displayText == "おはようございます")
    #expect(candidate?.appendText == "ます")
    #expect(candidate?.deleteCount == 1)
}

@Test func testMakePredictionCandidateKeepsDeleteCountZeroWithoutTrailingASCII() async throws {
    let candidate = SegmentsManager.makePredictionCandidate(
        currentTarget: "おはようござい",
        candidate: makeCandidate(text: "おはようございます", reading: "おはようございます")
    )

    #expect(candidate?.displayText == "おはようございます")
    #expect(candidate?.appendText == "ます")
    #expect(candidate?.deleteCount == 0)
}

@MainActor
@Test func testAcceptPredictionCandidateCompletesReadingAndContinuesRomanInput() throws {
    let manager = makePredictionSegmentsManager()
    manager.insertAtCursorPosition("hida", inputStyle: .roman2kana)
    manager.acceptPredictionCandidate(makeCandidate(text: "←", reading: "ひだり"))
    #expect(manager.convertTarget == "ひだり")

    manager.insertAtCursorPosition("nimagaru", inputStyle: .roman2kana)
    #expect(manager.convertTarget == "ひだりにまがる")
}

@MainActor
@Test func testAcceptPredictionCandidateReplacesPendingRomanSuffix() throws {
    let manager = makePredictionSegmentsManager()
    manager.insertAtCursorPosition("arigat", inputStyle: .roman2kana)
    manager.acceptPredictionCandidate(makeCandidate(text: "有難う", reading: "ありがとう"))

    #expect(manager.convertTarget == "ありがとう")
}

@MainActor
@Test func testAcceptPredictionCandidateRejectsStaleCandidateWithoutEditingInput() throws {
    let manager = makePredictionSegmentsManager()
    manager.insertAtCursorPosition("こんにちは", inputStyle: .direct)
    manager.acceptPredictionCandidate(makeCandidate(text: "今晩は", reading: "こんばんは"))

    #expect(manager.convertTarget == "こんにちは")
}

@MainActor
@Test func testAcceptTypoCorrectionPredictionCandidateReplacesReading() throws {
    let manager = makePredictionSegmentsManager()
    manager.insertAtCursorPosition("こんびんは", inputStyle: .direct)
    let prediction = try #require(SegmentsManager.makeBackspaceTypoCorrectionPredictionCandidate(
        currentConvertTarget: manager.convertTarget,
        targetReading: "こんばんは",
        displayText: "今晩は"
    ))

    manager.acceptTypoCorrectionPredictionCandidate(prediction)

    #expect(manager.convertTarget == "こんばんは")
}
