import Core
import Foundation
import Testing

@Test func converterServerEmptySnapshotHasNoVisibleComposition() {
    let snapshot = ConverterSessionSnapshot.empty

    #expect(snapshot.isEmpty)
    #expect(snapshot.convertTarget.isEmpty)
    #expect(snapshot.markedText.elements.isEmpty)
    #expect(snapshot.markedText.selectionRange.nsRange.location == NSNotFound)
    #expect(snapshot.markedText.selectionRange.nsRange.length == NSNotFound)

    guard case .hidden = snapshot.candidateWindow else {
        Issue.record("Expected hidden candidate window, got \(snapshot.candidateWindow)")
        return
    }
}

@Test func converterServerSnapshotCarriesPredictionCandidates() throws {
    let snapshot = ConverterSessionSnapshot(
        markedText: ConverterSessionSnapshot.empty.markedText,
        candidateWindow: .composing([], selectionIndex: nil),
        predictionCandidates: [
            .init(displayText: "ありがとう", appendText: "がとう", deleteCount: 0),
            .init(displayText: "明日", appendText: "した", deleteCount: 1)
        ],
        isEmpty: false,
        convertTarget: "あり"
    )

    let decoded = try ConverterServerCodec.decodeResponse(
        from: ConverterServerCodec.encode(
            ConverterServerResponse(snapshot: snapshot)
        )
    )

    #expect(decoded.snapshot.predictionCandidates.count == 2)
    #expect(decoded.snapshot.predictionCandidates[0].displayText == "ありがとう")
    #expect(decoded.snapshot.predictionCandidates[0].appendText == "がとう")
    #expect(decoded.snapshot.predictionCandidates[0].deleteCount == 0)
    #expect(decoded.snapshot.predictionCandidates[1].displayText == "明日")
    #expect(decoded.snapshot.predictionCandidates[1].appendText == "した")
    #expect(decoded.snapshot.predictionCandidates[1].deleteCount == 1)
}

@Test func converterServerHandleKeyEventCommandRoundTrips() throws {
    let request = ConverterKeyEventRequest(
        event: KeyEventCore(
            modifierFlags: [.shift],
            characters: "A",
            charactersIgnoringModifiers: "a",
            keyCode: 0
        ),
        inputState: .none,
        inputLanguage: .japanese,
        inputStyle: .defaultRomanToKana,
        liveConversionEnabled: true,
        enableDebugWindow: false,
        enableSuggestion: true,
        enablePredictiveTyping: true,
        enableTypoCorrection: true,
        leftSideContext: "左文脈",
        visibleCandidateStartIndex: 3
    )
    let command = ConverterServerCommand.handleKeyEvent(sessionID: "session-1", request: request)
    let roundTrip = try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(command))

    guard case .handleKeyEvent(let sessionID, let roundTripRequest) = roundTrip else {
        Issue.record("Expected handleKeyEvent command after round trip, got \(roundTrip)")
        return
    }
    #expect(sessionID == "session-1")
    #expect(roundTripRequest == request)
}

@Test func converterServerResponseCarriesClientEffects() throws {
    let response = ConverterServerResponse(
        handled: true,
        effects: [
            .insertText("あ"),
            .switchInputLanguage(.english),
            .requestReplaceSuggestion
        ],
        inputState: .composing,
        inputLanguage: .english,
        snapshot: .empty
    )
    let decoded = try ConverterServerCodec.decodeResponse(from: ConverterServerCodec.encode(response))

    #expect(decoded.handled)
    #expect(decoded.effects == response.effects)
    #expect(decoded.inputState == .composing)
    #expect(decoded.inputLanguage == .english)
}
