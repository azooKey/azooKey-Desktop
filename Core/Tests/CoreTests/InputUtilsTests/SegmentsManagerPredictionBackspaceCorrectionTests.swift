@testable import Core
import Testing

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
