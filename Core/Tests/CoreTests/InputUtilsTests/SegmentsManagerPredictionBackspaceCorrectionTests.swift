@testable import Core
import Testing

@Test func testBackspaceTypoFixPredictionCandidateReturnsCorrectedCandidate() async throws {
    let candidate = SegmentsManager.backspaceTypoFixPredictionCandidate(
        previousInput: "しょうしょうおまちくだしあ",
        previousFirstCandidateText: "少々お待ちくだしあ",
        currentInput: "しょうしょうおまちくだし"
    )

    #expect(candidate?.displayText == "少々お待ちください")
    #expect(candidate?.appendText == "さい")
    #expect(candidate?.deleteCount == 1)
}

@Test func testBackspaceTypoFixPredictionCandidateReturnsNilWhenSuffixDoesNotMatch() async throws {
    let candidate = SegmentsManager.backspaceTypoFixPredictionCandidate(
        previousInput: "しょうしょうおまちください",
        previousFirstCandidateText: "少々お待ちください",
        currentInput: "しょうしょうおまちくださ"
    )

    #expect(candidate == nil)
}

@Test func testBackspaceTypoFixPredictionCandidateFallsBackDisplayTextWhenCandidateSuffixDoesNotMatch() async throws {
    let candidate = SegmentsManager.backspaceTypoFixPredictionCandidate(
        previousInput: "やめてくだしあ",
        previousFirstCandidateText: "辞めて下さい",
        currentInput: "やめてくだし"
    )

    #expect(candidate?.displayText == "やめてください")
    #expect(candidate?.appendText == "さい")
    #expect(candidate?.deleteCount == 1)
}

@Test func testBackspaceTypoFixPredictionCandidateReturnsNilWhenCurrentInputIsNotPrefix() async throws {
    let candidate = SegmentsManager.backspaceTypoFixPredictionCandidate(
        previousInput: "しょうしょうおまちくだしあ",
        previousFirstCandidateText: "少々お待ちくだしあ",
        currentInput: "しょうしょうおまちください"
    )

    #expect(candidate == nil)
}

@Test func testShouldTriggerBackspaceTypoCorrectionReturnsFalseWhenBestCandidateMatchesCurrentInput() async throws {
    let shouldTrigger = SegmentsManager.shouldTriggerBackspaceTypoCorrection(
        deleteCount: 1,
        currentBestCandidateText: "くだし",
        currentInput: "くだし"
    )

    #expect(shouldTrigger == false)
}

@Test func testShouldTriggerBackspaceTypoCorrectionReturnsTrueWhenBestCandidateDiffersFromCurrentInput() async throws {
    let shouldTrigger = SegmentsManager.shouldTriggerBackspaceTypoCorrection(
        deleteCount: 1,
        currentBestCandidateText: "下さい",
        currentInput: "くだし"
    )

    #expect(shouldTrigger == true)
}

@Test func testShouldTriggerBackspaceTypoCorrectionReturnsFalseWhenDeleteCountIsNotOne() async throws {
    let shouldTrigger = SegmentsManager.shouldTriggerBackspaceTypoCorrection(
        deleteCount: 2,
        currentBestCandidateText: "下さい",
        currentInput: "くだし"
    )

    #expect(shouldTrigger == false)
}
