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

@Test func testPreferredPredictionCandidatesPreferTypoCorrectionCandidates() async throws {
    let typoCorrection = SegmentsManager.PredictionCandidate(
        displayText: "下さい",
        appendText: "さい",
        deleteCount: 1
    )
    let prediction = SegmentsManager.PredictionCandidate(
        displayText: "くださいました",
        appendText: "ました"
    )

    let candidates = SegmentsManager.preferredPredictionCandidates(
        typoCorrectionCandidates: [typoCorrection],
        predictionCandidates: [prediction]
    )

    #expect(candidates == [typoCorrection])
}

@Test func testPreferredPredictionCandidatesFallbackToPredictionCandidates() async throws {
    let prediction = SegmentsManager.PredictionCandidate(
        displayText: "くださいました",
        appendText: "ました"
    )

    let candidates = SegmentsManager.preferredPredictionCandidates(
        typoCorrectionCandidates: [],
        predictionCandidates: [prediction]
    )

    #expect(candidates == [prediction])
}
