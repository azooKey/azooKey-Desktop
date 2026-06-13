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
        enableOptionDirectFullWidthInput: true,
        typeBackSlash: true,
        optionDirectInputText: "a",
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

@Test func converterServerSessionConfigCommandRoundTrips() throws {
    let config = ConverterSessionConfig(
        aiBackendPreference: .openAI,
        openAIModelName: "gpt-test",
        openAIEndpoint: "https://api.example.test/v1",
        openAIAPIKey: .init("secret"),
        includeContextInAITransform: false
    )
    let command = ConverterServerCommand.updateSessionConfig(sessionID: "session-1", config: config)
    let roundTrip = try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(command))

    guard case .updateSessionConfig(let sessionID, let roundTripConfig) = roundTrip else {
        Issue.record("Expected updateSessionConfig command after round trip, got \(roundTrip)")
        return
    }
    #expect(sessionID == "session-1")
    #expect(roundTripConfig.aiBackendPreference == .openAI)
    #expect(roundTripConfig.openAIModelName == "gpt-test")
    #expect(roundTripConfig.openAIEndpoint == "https://api.example.test/v1")
    #expect(roundTripConfig.openAIAPIKey.value == "secret")
    #expect(roundTripConfig.openAIAPIKey.description == "<redacted>")
    #expect(!roundTripConfig.includeContextInAITransform)
}

@Test func converterServerReplaceSuggestionCommandsRoundTrip() throws {
    let request = ConverterServerCommand.requestReplaceSuggestion(sessionID: "session-1", leftSideContext: "左文脈")
    let select = ConverterServerCommand.selectReplaceSuggestionCandidate(sessionID: "session-1", index: 2)
    let submit = ConverterServerCommand.submitSelectedReplaceSuggestion(sessionID: "session-1")

    guard case .requestReplaceSuggestion(let requestSessionID, let leftSideContext) =
        try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(request)) else {
        Issue.record("Expected requestReplaceSuggestion command after round trip")
        return
    }
    #expect(requestSessionID == "session-1")
    #expect(leftSideContext == "左文脈")

    guard case .selectReplaceSuggestionCandidate(let selectSessionID, let index) =
        try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(select)) else {
        Issue.record("Expected selectReplaceSuggestionCandidate command after round trip")
        return
    }
    #expect(selectSessionID == "session-1")
    #expect(index == 2)

    guard case .submitSelectedReplaceSuggestion(let submitSessionID) =
        try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(submit)) else {
        Issue.record("Expected submitSelectedReplaceSuggestion command after round trip")
        return
    }
    #expect(submitSessionID == "session-1")
}

@Test func converterServerSettingsCommandsRoundTrip() throws {
    let capabilities = ConverterSettingClientCapabilities(
        supportedKinds: [.toggle, .selector, .button],
        supportedActions: ["resetLearningData"],
        supportedCustomSurfaces: ["inputStyle"]
    )
    let list = ConverterServerCommand.listSettings(sessionID: "session-1", capabilities: capabilities)
    let update = ConverterServerCommand.updateSetting(
        sessionID: "session-1",
        key: Config.TypeBackSlash.key,
        value: .bool(true)
    )

    guard case .listSettings(let listSessionID, let roundTripCapabilities) =
        try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(list)) else {
        Issue.record("Expected listSettings command after round trip")
        return
    }
    #expect(listSessionID == "session-1")
    #expect(roundTripCapabilities == capabilities)

    guard case .updateSetting(let updateSessionID, let key, let value) =
        try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(update)) else {
        Issue.record("Expected updateSetting command after round trip")
        return
    }
    #expect(updateSessionID == "session-1")
    #expect(key == Config.TypeBackSlash.key)
    #expect(value == .bool(true))
}

@Test func converterServerResponseCarriesClientEffects() throws {
    let setting = ConverterSettingDescriptor(
        key: Config.TypeBackSlash.key,
        title: "円記号の代わりにバックスラッシュを入力",
        section: "入力オプション",
        kind: .toggle,
        value: .bool(true),
        requiresClientUpdate: false
    )
    let response = ConverterServerResponse(
        handled: true,
        effects: [
            .insertText("あ"),
            .switchInputLanguage(.english),
            .requestReplaceSuggestion
        ],
        inputState: .composing,
        inputLanguage: .english,
        settings: [setting],
        snapshot: .empty
    )
    let decoded = try ConverterServerCodec.decodeResponse(from: ConverterServerCodec.encode(response))

    #expect(decoded.handled)
    #expect(decoded.effects == response.effects)
    #expect(decoded.inputState == .composing)
    #expect(decoded.inputLanguage == .english)
    #expect(decoded.settings == [setting])
}
