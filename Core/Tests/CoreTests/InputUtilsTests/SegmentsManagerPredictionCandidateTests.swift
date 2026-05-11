@testable import Core
import Testing

@Test func testMakePredictionCandidateDeletesTrailingASCIIUsedForMatching() async throws {
    let candidate = SegmentsManager.makePredictionCandidate(
        currentTarget: "おはようございm",
        candidateReading: "おはようございます",
        displayText: "おはようございます"
    )

    #expect(candidate?.displayText == "おはようございます")
    #expect(candidate?.appendText == "ます")
    #expect(candidate?.deleteCount == 1)
}

@Test func testMakePredictionCandidateKeepsDeleteCountZeroWithoutTrailingASCII() async throws {
    let candidate = SegmentsManager.makePredictionCandidate(
        currentTarget: "おはようござい",
        candidateReading: "おはようございます",
        displayText: "おはようございます"
    )

    #expect(candidate?.displayText == "おはようございます")
    #expect(candidate?.appendText == "ます")
    #expect(candidate?.deleteCount == 0)
}
