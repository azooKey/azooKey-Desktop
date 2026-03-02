@testable import Core
import Testing

@Test func testMakeBackspaceTypoCorrectionPredictionCandidateRecalculatesEditOperationForCurrentInput() async throws {
    let candidate = SegmentsManager.makeBackspaceTypoCorrectionPredictionCandidate(
        currentInput: "くだし",
        targetReading: "ください",
        displayText: "下さい"
    )

    #expect(candidate?.displayText == "下さい")
    #expect(candidate?.appendText == "さい")
    #expect(candidate?.deleteCount == 1)
}

@Test func testMakeBackspaceTypoCorrectionPredictionCandidateKeepsDisplayTextAndUpdatesAppendTextOnFurtherDelete() async throws {
    let candidate = SegmentsManager.makeBackspaceTypoCorrectionPredictionCandidate(
        currentInput: "くだ",
        targetReading: "ください",
        displayText: "下さい"
    )

    #expect(candidate?.displayText == "下さい")
    #expect(candidate?.appendText == "さい")
    #expect(candidate?.deleteCount == 0)
}
