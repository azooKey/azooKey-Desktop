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
        context: .init(leftSideContext: "左文脈", rightSideContext: "右文脈"),
        visibleCandidateStartIndex: 3
    )
    let command = ConverterServerCommand.session(sessionID: "session-1", command: .handleKeyEvent(request))
    let roundTrip = try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(command))

    guard case .session(let sessionID, .handleKeyEvent(let roundTripRequest)) = roundTrip else {
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
    let command = ConverterServerCommand.session(sessionID: "session-1", command: .updateConfig(config))
    let roundTrip = try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(command))

    guard case .session(let sessionID, .updateConfig(let roundTripConfig)) = roundTrip else {
        Issue.record("Expected updateConfig command after round trip, got \(roundTrip)")
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
    let request = ConverterServerCommand.session(
        sessionID: "session-1",
        command: .replaceSuggestion(.request(context: .init(leftSideContext: "左文脈", rightSideContext: "右文脈")))
    )
    let select = ConverterServerCommand.session(
        sessionID: "session-1",
        command: .replaceSuggestion(.selectReplaceSuggestionCandidate(index: 2))
    )
    let submit = ConverterServerCommand.session(
        sessionID: "session-1",
        command: .replaceSuggestion(.submitSelectedReplaceSuggestion)
    )

    guard case .session(let requestSessionID, .replaceSuggestion(.request(let context))) =
            try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(request)) else {
        Issue.record("Expected requestReplaceSuggestion command after round trip")
        return
    }
    #expect(requestSessionID == "session-1")
    #expect(context.leftSideContext == "左文脈")
    #expect(context.rightSideContext == "右文脈")

    guard case .session(let selectSessionID, .replaceSuggestion(.selectReplaceSuggestionCandidate(let index))) =
            try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(select)) else {
        Issue.record("Expected selectReplaceSuggestionCandidate command after round trip")
        return
    }
    #expect(selectSessionID == "session-1")
    #expect(index == 2)

    guard case .session(let submitSessionID, .replaceSuggestion(.submitSelectedReplaceSuggestion)) =
            try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(submit)) else {
        Issue.record("Expected submitSelectedReplaceSuggestion command after round trip")
        return
    }
    #expect(submitSessionID == "session-1")
}

@Test func converterServerCandidateCommandsRoundTripContext() throws {
    let context = ConverterTextContext(leftSideContext: "左文脈", rightSideContext: "右文脈")
    let submit = ConverterServerCommand.session(
        sessionID: "session-1",
        command: .candidate(.submitSelectedCandidate(context: context))
    )

    guard case .session(let sessionID, .candidate(.submitSelectedCandidate(let roundTripContext))) =
            try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(submit)) else {
        Issue.record("Expected submitSelectedCandidate command after round trip")
        return
    }
    #expect(sessionID == "session-1")
    #expect(roundTripContext == context)
}

@Test func converterServerSettingsCommandsRoundTrip() throws {
    guard case .shutdown = try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(.shutdown)) else {
        Issue.record("Expected shutdown command after round trip")
        return
    }

    let capabilities = ConverterSettingClientCapabilities(
        supportedKinds: [.toggle, .selector, .button],
        supportedActions: ["resetLearningData"],
        supportedCustomSurfaces: ["inputStyle"]
    )
    let list = ConverterServerCommand.session(
        sessionID: "session-1",
        command: .settings(.list(capabilities: capabilities))
    )
    let update = ConverterServerCommand.session(
        sessionID: "session-1",
        command: .settings(.update(
            key: Config.TypeBackSlash.key,
            value: .bool(true)
        ))
    )

    guard case .session(let listSessionID, .settings(.list(let roundTripCapabilities))) =
            try ConverterServerCodec.decodeCommand(from: ConverterServerCodec.encode(list)) else {
        Issue.record("Expected listSettings command after round trip")
        return
    }
    #expect(listSessionID == "session-1")
    #expect(roundTripCapabilities == capabilities)

    guard case .session(let updateSessionID, .settings(.update(let key, let value))) =
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
