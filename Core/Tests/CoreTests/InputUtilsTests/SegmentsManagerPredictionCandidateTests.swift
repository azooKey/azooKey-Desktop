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
    #expect(candidate?.candidate == source)
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
    let prediction = try #require(SegmentsManager.makePredictionCandidate(
        currentTarget: manager.convertTarget,
        candidate: makeCandidate(text: "←", reading: "ひだり")
    ))

    manager.acceptPredictionCandidate(prediction)
    #expect(manager.convertTarget == "ひだり")

    manager.insertAtCursorPosition("nimagaru", inputStyle: .roman2kana)
    #expect(manager.convertTarget == "ひだりにまがる")
}

@MainActor
@Test func testAcceptPredictionCandidateReplacesPendingRomanSuffix() throws {
    let manager = makePredictionSegmentsManager()
    manager.insertAtCursorPosition("arigat", inputStyle: .roman2kana)
    let prediction = try #require(SegmentsManager.makePredictionCandidate(
        currentTarget: manager.convertTarget,
        candidate: makeCandidate(text: "有難う", reading: "ありがとう")
    ))

    manager.acceptPredictionCandidate(prediction)

    #expect(manager.convertTarget == "ありがとう")
}

@MainActor
@Test func testAcceptPredictionCandidateRejectsStaleCandidateWithoutEditingInput() throws {
    let manager = makePredictionSegmentsManager()
    manager.insertAtCursorPosition("こんにちは", inputStyle: .direct)
    let prediction = try #require(SegmentsManager.makePredictionCandidate(
        currentTarget: "こんば",
        candidate: makeCandidate(text: "今晩は", reading: "こんばんは")
    ))

    manager.acceptPredictionCandidate(prediction)

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

    manager.acceptPredictionCandidate(prediction)

    #expect(manager.convertTarget == "こんばんは")
}
