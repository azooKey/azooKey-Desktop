@testable import Core
import Testing

@Test func testMakeBackspaceTypoCorrectionPredictionCandidateRecalculatesEditOperationForCurrentInput() async throws {
    let candidate = SegmentsManager.makeBackspaceTypoCorrectionPredictionCandidate(
        currentConvertTarget: "くだし",
        targetReading: "ください",
        displayText: "下さい"
    )

    #expect(candidate?.displayText == "下さい")
    #expect(candidate?.appendText == "さい")
    #expect(candidate?.deleteCount == 1)
}

@Test func testMakeBackspaceTypoCorrectionPredictionCandidateKeepsDisplayTextAndUpdatesAppendTextOnFurtherDelete() async throws {
    let candidate = SegmentsManager.makeBackspaceTypoCorrectionPredictionCandidate(
        currentConvertTarget: "くだ",
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

@Test func testShouldPresentTypoCorrectionPredictionCandidateReturnsFalseForMatchingPreviousComposingDisplay() async throws {
    // 削除前の previousComposingText と同じ表示候補は、訂正候補として出さない。
    let shouldPresent = SegmentsManager.shouldPresentTypoCorrectionPredictionCandidate(
        candidateDisplayText: "下さい",
        previousComposingDisplayText: "下さい"
    )

    #expect(shouldPresent == false)
}

@Test func testShouldPresentTypoCorrectionPredictionCandidateReturnsTrueForDifferentPreviousComposingDisplay() async throws {
    // 削除前の previousComposingText と異なる表示候補だけを、訂正候補として出す。
    let shouldPresent = SegmentsManager.shouldPresentTypoCorrectionPredictionCandidate(
        candidateDisplayText: "下さい",
        previousComposingDisplayText: "ください"
    )

    #expect(shouldPresent == true)
}
