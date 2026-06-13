import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

extension ConverterServer {
    @MainActor
    func handleKeyEvent(
        sessionID: String,
        request: ConverterKeyEventRequest
    ) throws -> ConverterServerResponse {
        let session = try getSession(sessionID)
        session.setContext(request.context)
        Config.DebugPredictiveTyping().value = request.enablePredictiveTyping
        Config.DebugTypoCorrection().value = request.enableTypoCorrection

        if request.enableOptionDirectFullWidthInput,
           let text = OptionDirectInputResolver.resolve(
            characters: request.optionDirectInputText,
            modifierFlags: request.event.modifierFlags,
            inputLanguage: request.inputLanguage,
            inputState: request.inputState.inputState,
            typeBackSlash: request.typeBackSlash
           ) {
            return ConverterServerResponse(
                effects: [.insertText(text)],
                inputState: request.inputState,
                inputLanguage: request.inputLanguage,
                snapshot: snapshot(for: session, inputState: request.inputState.inputState)
            )
        }

        let userAction = UserAction.getUserAction(
            eventCore: request.event,
            inputLanguage: request.inputLanguage,
            typeBackSlash: request.typeBackSlash
        )
        let (clientAction, clientActionCallback) = request.inputState.inputState.event(
            eventCore: request.event,
            userAction: userAction,
            inputLanguage: request.inputLanguage,
            liveConversionEnabled: request.liveConversionEnabled,
            enableDebugWindow: request.enableDebugWindow,
            enableSuggestion: request.enableSuggestion
        )

        var effects: [ConverterClientEffect] = []
        var inputLanguage = request.inputLanguage
        let actionHandled = perform(
            clientAction,
            request: request,
            session: session,
            inputLanguage: &inputLanguage,
            effects: &effects
        )
        guard actionHandled else {
            return ConverterServerResponse(
                handled: false,
                effects: effects,
                inputState: request.inputState,
                inputLanguage: inputLanguage,
                snapshot: snapshot(for: session, inputState: request.inputState.inputState)
            )
        }

        let nextInputState = apply(
            clientActionCallback,
            currentInputState: request.inputState.inputState,
            compositionIsEmpty: session.manager.isEmpty
        )
        return ConverterServerResponse(
            handled: !effects.contains(.fallthroughToApplication),
            effects: effects,
            inputState: ConverterInputState(nextInputState),
            inputLanguage: inputLanguage,
            snapshot: snapshot(for: session, inputState: nextInputState)
        )
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func perform(
        _ action: ClientAction,
        request: ConverterKeyEventRequest,
        session: ConverterSession,
        inputLanguage: inout InputLanguage,
        effects: inout [ConverterClientEffect]
    ) -> Bool {
        let manager = session.manager
        let inputState = request.inputState.inputState
        let inputStyle = Self.resolveInputStyle(request.inputLanguage == .english ? .direct : request.inputStyle)
        let leftSideContext = session.conversionLeftSideContext()
        switch action {
        case .consume:
            return true
        case .fallthrough:
            effects.append(.fallthroughToApplication)
            return true
        case .showCandidateWindow:
            manager.requestSetCandidateWindowState(visible: true)
        case .hideCandidateWindow:
            manager.requestSetCandidateWindowState(visible: false)
        case .appendToMarkedText(let text):
            manager.insertAtCursorPosition(text, inputStyle: inputStyle)
        case .appendPieceToMarkedText(let pieces):
            manager.insertAtCursorPosition(pieces: pieces, inputStyle: inputStyle)
        case .insertWithoutMarkedText(let text):
            effects.append(.insertText(text))
        case .removeLastMarkedText:
            manager.deleteBackwardFromCursorPosition()
            manager.requestResettingSelection()
        case .commitMarkedText:
            let text = manager.commitMarkedText(inputState: inputState)
            if !text.isEmpty {
                effects.append(.insertText(text))
            }
        case .editSegment(let count):
            manager.editSegment(count: count)
        case .enterFirstCandidatePreviewMode:
            manager.insertCompositionSeparator(inputStyle: inputStyle, skipUpdate: false)
            manager.requestSetCandidateWindowState(visible: false)
        case .enterCandidateSelectionMode:
            manager.insertCompositionSeparator(inputStyle: inputStyle, skipUpdate: true)
            manager.update(requestRichCandidates: true)
        case .submitSelectedCandidate:
            submitSelectedCandidate(manager: manager, leftSideContext: leftSideContext, effects: &effects)
        case .selectNextCandidate:
            manager.requestSelectingNextCandidate()
        case .selectPrevCandidate:
            manager.requestSelectingPrevCandidate()
        case .selectNumberCandidate(let number):
            manager.requestSelectingRow(request.visibleCandidateStartIndex + number - 1)
            submitSelectedCandidate(manager: manager, leftSideContext: leftSideContext, effects: &effects)
            manager.requestResettingSelection()
        case .selectInputLanguage(let language):
            inputLanguage = language
            effects.append(.switchInputLanguage(language))
        case .commitMarkedTextAndSelectInputLanguage(let language):
            let text = manager.commitMarkedText(inputState: inputState)
            if !text.isEmpty {
                effects.append(.insertText(text))
            }
            inputLanguage = language
            effects.append(.switchInputLanguage(language))
        case .commitMarkedTextAndAppendToMarkedText(let text):
            commitMarkedTextAndContinue(
                manager: manager,
                inputState: inputState,
                effects: &effects
            )
            manager.insertAtCursorPosition(text, inputStyle: inputStyle)
        case .commitMarkedTextAndAppendPieceToMarkedText(let pieces):
            commitMarkedTextAndContinue(
                manager: manager,
                inputState: inputState,
                effects: &effects
            )
            manager.insertAtCursorPosition(pieces: pieces, inputStyle: inputStyle)
        case .enableDebugWindow:
            manager.requestDebugWindowMode(enabled: true)
        case .disableDebugWindow:
            manager.requestDebugWindowMode(enabled: false)
        case .forgetMemory:
            manager.forgetMemory()
        case .submitKatakanaCandidate:
            submitTransformedCandidate(.katakana, manager: manager, inputState: inputState, leftSideContext: leftSideContext, effects: &effects)
        case .submitHiraganaCandidate:
            submitTransformedCandidate(.hiragana, manager: manager, inputState: inputState, leftSideContext: leftSideContext, effects: &effects)
        case .submitHankakuKatakanaCandidate:
            submitTransformedCandidate(.halfWidthKatakana, manager: manager, inputState: inputState, leftSideContext: leftSideContext, effects: &effects)
        case .submitFullWidthRomanCandidate:
            submitTransformedCandidate(.fullWidthRoman, manager: manager, inputState: inputState, leftSideContext: leftSideContext, effects: &effects)
        case .submitHalfWidthRomanCandidate:
            submitTransformedCandidate(.halfWidthRoman, manager: manager, inputState: inputState, leftSideContext: leftSideContext, effects: &effects)
        case .requestPredictiveSuggestion:
            manager.insertAtCursorPosition("つづき", inputStyle: inputStyle)
            effects.append(.requestReplaceSuggestion)
        case .acceptPredictionCandidate:
            acceptPredictionCandidate(manager: manager, leftSideContext: leftSideContext)
        case .requestReplaceSuggestion:
            session.clearReplaceSuggestions()
            effects.append(.requestReplaceSuggestion)
        case .selectNextReplaceSuggestionCandidate:
            session.selectNextReplaceSuggestion()
        case .selectPrevReplaceSuggestionCandidate:
            session.selectPreviousReplaceSuggestion()
        case .submitReplaceSuggestionCandidate:
            _ = submitSelectedReplaceSuggestion(session: session, effects: &effects)
        case .hideReplaceSuggestionWindow:
            session.clearReplaceSuggestions()
            effects.append(.hideReplaceSuggestionWindow)
        case .showPromptInputWindow:
            effects.append(.showPromptInputWindow)
        case .transformSelectedText(let selectedText, let prompt):
            effects.append(.transformSelectedText(selectedText, prompt))
        case .enterUnicodeInputMode, .appendToUnicodeInput, .removeLastUnicodeInput, .cancelUnicodeInput:
            return true
        case .submitUnicodeInput(let codePoint):
            if let scalar = UInt32(codePoint, radix: 16), let unicodeScalar = Unicode.Scalar(scalar) {
                effects.append(.insertText(String(Character(unicodeScalar))))
            }
        case .submitSelectedCandidateAndEnterUnicodeInputMode:
            submitSelectedCandidate(manager: manager, leftSideContext: leftSideContext, effects: &effects)
            if !manager.isEmpty {
                effects.append(.insertText(manager.convertTarget))
                manager.stopComposition()
            }
        case .stopComposition:
            manager.stopComposition()
        }
        return true
    }

    @MainActor
    func apply(
        _ callback: ClientActionCallback,
        currentInputState: InputState,
        compositionIsEmpty: Bool
    ) -> InputState {
        switch callback {
        case .fallthrough:
            return currentInputState
        case .transition(let inputState):
            return inputState
        case .basedOnBackspace(let ifIsEmpty, let ifIsNotEmpty),
             .basedOnSubmitCandidate(let ifIsEmpty, let ifIsNotEmpty):
            return compositionIsEmpty ? ifIsEmpty : ifIsNotEmpty
        }
    }

    @MainActor
    func commitMarkedTextAndContinue(
        manager: SegmentsManager,
        inputState: InputState,
        effects: inout [ConverterClientEffect]
    ) {
        let text = manager.commitMarkedText(inputState: inputState)
        if !text.isEmpty {
            effects.append(.insertText(text))
        }
    }

    @MainActor
    func submitSelectedCandidate(
        manager: SegmentsManager,
        leftSideContext: String?,
        effects: inout [ConverterClientEffect]
    ) {
        guard let candidate = manager.selectedCandidate else {
            return
        }
        manager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext ?? "")
        effects.append(.insertText(candidate.text))
    }

    @MainActor
    func submitTransformedCandidate(
        _ transform: ConverterCandidateTransform,
        manager: SegmentsManager,
        inputState: InputState,
        leftSideContext: String?,
        effects: inout [ConverterClientEffect]
    ) {
        let candidate = Self.transformedCandidate(transform, manager: manager, inputState: inputState)
        manager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext ?? "")
        effects.append(.insertText(candidate.text))
    }

    @MainActor
    func requestReplaceSuggestion(
        session: ConverterSession
    ) async throws {
        session.clearReplaceSuggestions()
        guard !session.manager.isEmpty else {
            return
        }
        let backend: AIBackend
        switch session.config.aiBackendPreference {
        case .off:
            return
        case .foundationModels:
            backend = .foundationModels
        case .openAI:
            backend = .openAI
        }
        let composingText = session.manager.convertTarget
        let prompt = session.config.includeContextInAITransform ? session.replaceSuggestionPromptContext() : ""
        let request = OpenAIRequest(
            prompt: prompt,
            target: composingText,
            modelName: session.config.openAIModelName.isEmpty ? Config.OpenAiModelName.default : session.config.openAIModelName
        )
        let predictions = try await AIClient.sendRequest(
            request,
            backend: backend,
            apiKey: session.config.openAIAPIKey.value,
            apiEndpoint: session.config.openAIEndpoint.isEmpty ? Config.OpenAiApiEndpoint.default : session.config.openAIEndpoint
        )
        guard session.manager.convertTarget == composingText else {
            return
        }
        session.replaceSuggestions = predictions.map { text in
            Candidate(
                text: text,
                value: PValue(0),
                composingCount: .surfaceCount(composingText.count),
                lastMid: 0,
                data: [],
                actions: [],
                inputable: true
            )
        }
        if !session.replaceSuggestions.isEmpty {
            session.replaceSuggestionSelectionIndex = 0
        }
    }

    @MainActor
    func submitSelectedReplaceSuggestion(
        session: ConverterSession,
        effects: inout [ConverterClientEffect]
    ) -> Bool {
        guard let candidate = session.selectedReplaceSuggestion else {
            return false
        }
        effects.append(.insertText(candidate.text))
        session.manager.stopComposition()
        session.clearReplaceSuggestions()
        return true
    }

    @MainActor
    func acceptPredictionCandidate(manager: SegmentsManager, leftSideContext _: String?) {
        let prediction = SegmentsManager.preferredPredictionCandidates(
            typoCorrectionCandidates: manager.requestTypoCorrectionPredictionCandidates(),
            predictionCandidates: manager.requestPredictionCandidates()
        ).first
        guard let prediction else {
            return
        }
        if prediction.deleteCount > 0 {
            manager.deleteBackwardFromCursorPosition(count: prediction.deleteCount)
        }
        guard !prediction.appendText.isEmpty else {
            return
        }
        manager.insertAtCursorPosition(prediction.appendText, inputStyle: .direct)
    }
}
