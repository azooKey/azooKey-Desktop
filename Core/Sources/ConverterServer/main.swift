import Core
import Darwin
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

private enum ConverterServerXPC {
    static let machServiceName = "dev.ensan.inputmethod.azooKeyMac.ConverterServer"
}

private enum ConverterCandidateTransform {
    case hiragana
    case katakana
    case halfWidthKatakana
    case fullWidthRoman
    case halfWidthRoman
}

@objc private protocol ConverterServerXPCProtocol {
    func openSession(with reply: @escaping @Sendable (String) -> Void)
    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void)
    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void)
    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void)
}

private final class ConverterSession: SegmentManagerDelegate {
    let manager: SegmentsManager
    private var leftSideContext: String?
    var config = ConverterSessionConfig(
        aiBackendPreference: .off,
        openAIModelName: Config.OpenAiModelName.default,
        openAIEndpoint: Config.OpenAiApiEndpoint.default,
        openAIAPIKey: .init(""),
        includeContextInAITransform: true
    )
    var replaceSuggestions: [Candidate] = []
    var replaceSuggestionSelectionIndex: Int?

    init(manager: SegmentsManager) {
        self.manager = manager
        self.manager.delegate = self
    }

    func setLeftSideContext(_ value: String?) {
        self.leftSideContext = value
    }

    func getLeftSideContext(maxCount: Int) -> String? {
        guard let leftSideContext else {
            return nil
        }
        return String(leftSideContext.suffix(maxCount))
    }

    func clearReplaceSuggestions() {
        self.replaceSuggestions = []
        self.replaceSuggestionSelectionIndex = nil
    }

    func selectReplaceSuggestion(at index: Int) {
        guard !replaceSuggestions.isEmpty else {
            replaceSuggestionSelectionIndex = nil
            return
        }
        replaceSuggestionSelectionIndex = min(max(0, index), replaceSuggestions.count - 1)
    }

    func selectNextReplaceSuggestion() {
        guard !replaceSuggestions.isEmpty else {
            replaceSuggestionSelectionIndex = nil
            return
        }
        replaceSuggestionSelectionIndex = ((replaceSuggestionSelectionIndex ?? -1) + 1) % replaceSuggestions.count
    }

    func selectPreviousReplaceSuggestion() {
        guard !replaceSuggestions.isEmpty else {
            replaceSuggestionSelectionIndex = nil
            return
        }
        let current = replaceSuggestionSelectionIndex ?? 0
        replaceSuggestionSelectionIndex = (current - 1 + replaceSuggestions.count) % replaceSuggestions.count
    }

    var selectedReplaceSuggestion: Candidate? {
        guard let replaceSuggestionSelectionIndex,
              replaceSuggestions.indices.contains(replaceSuggestionSelectionIndex) else {
            return nil
        }
        return replaceSuggestions[replaceSuggestionSelectionIndex]
    }
}

private final class ConverterServer: NSObject, ConverterServerXPCProtocol, @unchecked Sendable {
    private var sessions: [String: ConverterSession] = [:]

    func openSession(with reply: @escaping @Sendable (String) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let sessionID = UUID().uuidString
                self.sessions[sessionID] = ConverterSession(manager: Self.makeSegmentsManager())
                reply(sessionID)
            }
        }
    }

    func closeSession(_ sessionID: String, with reply: @escaping @Sendable (Bool) -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let removed = self.sessions.removeValue(forKey: sessionID) != nil
                reply(removed)
            }
        }
    }

    func ping(_ message: String, with reply: @escaping @Sendable (String) -> Void) {
        reply("ConverterServer: \(message)")
    }

    func handleCommand(_ data: Data, with reply: @escaping @Sendable (Data?, NSString?) -> Void) {
        Task { @MainActor in
            do {
                let command = try ConverterServerCodec.decodeCommand(from: data)
                let response = try await self.handle(command)
                reply(try ConverterServerCodec.encode(response), nil)
            } catch {
                reply(nil, error.localizedDescription as NSString)
            }
        }
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    private func handle(_ command: ConverterServerCommand) async throws -> ConverterServerResponse {
        switch command {
        case .shutdown:
            Self.scheduleShutdown()
            return ConverterServerResponse(snapshot: .empty)
        case .activate(let sessionID):
            let session = try getSession(sessionID)
            session.manager.activate()
            return makeResponse(for: session, inputState: .none)
        case .deactivate(let sessionID):
            let session = try getSession(sessionID)
            session.manager.deactivate()
            return makeResponse(for: session, inputState: .none)
        case .listSettings(let sessionID, let capabilities):
            let session = try getSession(sessionID)
            return makeResponse(
                for: session,
                inputState: .none,
                settings: Self.makeSettingDescriptors(capabilities: capabilities)
            )
        case .updateSetting(let sessionID, let key, let value):
            let session = try getSession(sessionID)
            try Self.updateSetting(key: key, value: value)
            return makeResponse(for: session, inputState: .none)
        case .snapshot(let sessionID, let inputState):
            return makeResponse(for: try getSession(sessionID), inputState: inputState.inputState)
        case .stopComposition(let sessionID):
            let session = try getSession(sessionID)
            session.manager.stopComposition()
            return makeResponse(for: session, inputState: .none)
        case .forgetMemory(let sessionID):
            let session = try getSession(sessionID)
            session.manager.forgetMemory()
            return makeResponse(for: session, inputState: .none)
        case .updateSessionConfig(let sessionID, let config):
            let session = try getSession(sessionID)
            session.config = config
            return makeResponse(for: session, inputState: .none)
        case .handleKeyEvent(let sessionID, let request):
            return try handleKeyEvent(sessionID: sessionID, request: request)
        case .selectCandidate(let sessionID, let index):
            let session = try getSession(sessionID)
            session.manager.requestSelectingRow(index)
            return makeResponse(for: session, inputState: .selecting)
        case .submitSelectedCandidate(let sessionID, let leftSideContext):
            let session = try getSession(sessionID)
            var effects: [ConverterClientEffect] = []
            submitSelectedCandidate(manager: session.manager, leftSideContext: leftSideContext, effects: &effects)
            let nextInputState: InputState = session.manager.isEmpty ? .none : .previewing
            return makeResponse(
                for: session,
                inputState: nextInputState,
                effects: effects,
                responseInputState: ConverterInputState(nextInputState)
            )
        case .commitComposition(let sessionID, let inputState):
            let session = try getSession(sessionID)
            let text = session.manager.commitMarkedText(inputState: inputState.inputState)
            let effects: [ConverterClientEffect] = text.isEmpty ? [] : [.insertText(text)]
            return makeResponse(for: session, inputState: .none, effects: effects, responseInputState: ConverterInputState.none)
        case .requestReplaceSuggestion(let sessionID, let leftSideContext):
            let session = try getSession(sessionID)
            try await requestReplaceSuggestion(session: session, leftSideContext: leftSideContext)
            return makeResponse(for: session, inputState: .replaceSuggestion, responseInputState: .replaceSuggestion)
        case .selectReplaceSuggestionCandidate(let sessionID, let index):
            let session = try getSession(sessionID)
            session.selectReplaceSuggestion(at: index)
            return makeResponse(for: session, inputState: .replaceSuggestion, responseInputState: .replaceSuggestion)
        case .submitSelectedReplaceSuggestion(let sessionID):
            let session = try getSession(sessionID)
            var effects: [ConverterClientEffect] = []
            let didSubmit = submitSelectedReplaceSuggestion(session: session, effects: &effects)
            let nextInputState: InputState = didSubmit ? .none : .replaceSuggestion
            return makeResponse(
                for: session,
                inputState: nextInputState,
                effects: effects,
                responseInputState: ConverterInputState(nextInputState)
            )
        }
    }

    @MainActor
    private func handleKeyEvent(
        sessionID: String,
        request: ConverterKeyEventRequest
    ) throws -> ConverterServerResponse {
        guard let session = sessions[sessionID] else {
            throw ConverterServerError.unknownSession(sessionID)
        }
        session.setLeftSideContext(request.leftSideContext)
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
    private func perform(
        _ action: ClientAction,
        request: ConverterKeyEventRequest,
        session: ConverterSession,
        inputLanguage: inout InputLanguage,
        effects: inout [ConverterClientEffect]
    ) -> Bool {
        let manager = session.manager
        let inputState = request.inputState.inputState
        let inputStyle = Self.resolveInputStyle(request.inputLanguage == .english ? .direct : request.inputStyle)
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
            submitSelectedCandidate(manager: manager, leftSideContext: request.leftSideContext, effects: &effects)
        case .selectNextCandidate:
            manager.requestSelectingNextCandidate()
        case .selectPrevCandidate:
            manager.requestSelectingPrevCandidate()
        case .selectNumberCandidate(let number):
            manager.requestSelectingRow(request.visibleCandidateStartIndex + number - 1)
            submitSelectedCandidate(manager: manager, leftSideContext: request.leftSideContext, effects: &effects)
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
            submitTransformedCandidate(.katakana, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .submitHiraganaCandidate:
            submitTransformedCandidate(.hiragana, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .submitHankakuKatakanaCandidate:
            submitTransformedCandidate(.halfWidthKatakana, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .submitFullWidthRomanCandidate:
            submitTransformedCandidate(.fullWidthRoman, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .submitHalfWidthRomanCandidate:
            submitTransformedCandidate(.halfWidthRoman, manager: manager, inputState: inputState, leftSideContext: request.leftSideContext, effects: &effects)
        case .requestPredictiveSuggestion:
            manager.insertAtCursorPosition("つづき", inputStyle: inputStyle)
            effects.append(.requestReplaceSuggestion)
        case .acceptPredictionCandidate:
            acceptPredictionCandidate(manager: manager, leftSideContext: request.leftSideContext)
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
            submitSelectedCandidate(manager: manager, leftSideContext: request.leftSideContext, effects: &effects)
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
    private func apply(
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
    private func commitMarkedTextAndContinue(
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
    private func submitSelectedCandidate(
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
    private func submitTransformedCandidate(
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
    private func requestReplaceSuggestion(
        session: ConverterSession,
        leftSideContext: String?
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
        let prompt = session.config.includeContextInAITransform ? (leftSideContext ?? "") : ""
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
    private func submitSelectedReplaceSuggestion(
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
    private func acceptPredictionCandidate(manager: SegmentsManager, leftSideContext _: String?) {
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

    @MainActor
    private static func makeSettingDescriptors(
        capabilities: ConverterSettingClientCapabilities
    ) -> [ConverterSettingDescriptor] {
        func descriptor(
            key: String,
            title: String,
            section: String,
            kind: ConverterSettingKind,
            value: ConverterSettingValue? = nil,
            isEnabled: Bool = true
        ) -> ConverterSettingDescriptor {
            ConverterSettingDescriptor(
                key: key,
                title: title,
                section: section,
                kind: kind,
                value: value,
                isEnabled: isEnabled,
                requiresClientUpdate: requiresClientUpdate(kind: kind, capabilities: capabilities)
            )
        }

        return [
            descriptor(
                key: Config.AIBackendPreference.key,
                title: "いい感じ変換",
                section: "基本",
                kind: .selector(options: [
                    .init(title: "オフ", value: .string(Config.AIBackendPreference.Value.off.rawValue)),
                    .init(title: "Foundation Models", value: .string(Config.AIBackendPreference.Value.foundationModels.rawValue)),
                    .init(title: "OpenAI API", value: .string(Config.AIBackendPreference.Value.openAI.rawValue))
                ]),
                value: .string(Config.AIBackendPreference().value.rawValue)
            ),
            descriptor(
                key: Config.LiveConversion.key,
                title: "ライブ変換",
                section: "変換設定",
                kind: .toggle,
                value: .bool(Config.LiveConversion().value)
            ),
            descriptor(
                key: Config.TypeBackSlash.key,
                title: "円記号の代わりにバックスラッシュを入力",
                section: "入力オプション",
                kind: .toggle,
                value: .bool(Config.TypeBackSlash().value)
            ),
            descriptor(
                key: Config.TypeHalfSpace.key,
                title: "スペースは常に半角を入力",
                section: "入力オプション",
                kind: .toggle,
                value: .bool(Config.TypeHalfSpace().value)
            ),
            descriptor(
                key: Config.OptionDirectFullWidthInput.key,
                title: "Optionキーで直接全角英数を入力",
                section: "入力オプション",
                kind: .toggle,
                value: .bool(Config.OptionDirectFullWidthInput().value)
            ),
            descriptor(
                key: Config.PunctuationStyle.key,
                title: "句読点の種類",
                section: "入力オプション",
                kind: .selector(options: [
                    .init(title: "、と。", value: .int(Config.PunctuationStyle.Value.kutenAndToten.rawValue)),
                    .init(title: "、と．", value: .int(Config.PunctuationStyle.Value.periodAndToten.rawValue)),
                    .init(title: "，と。", value: .int(Config.PunctuationStyle.Value.kutenAndComma.rawValue)),
                    .init(title: "，と．", value: .int(Config.PunctuationStyle.Value.periodAndComma.rawValue))
                ]),
                value: .int(Config.PunctuationStyle().value.rawValue)
            ),
            descriptor(
                key: Config.Learning.key,
                title: "履歴学習",
                section: "履歴学習",
                kind: .selector(options: [
                    .init(title: "学習する", value: .string(Config.Learning.Value.inputAndOutput.rawValue)),
                    .init(title: "学習を停止", value: .string(Config.Learning.Value.onlyOutput.rawValue)),
                    .init(title: "学習を無視", value: .string(Config.Learning.Value.nothing.rawValue))
                ]),
                value: .string(Config.Learning().value.rawValue)
            ),
            descriptor(
                key: "dev.ensan.inputmethod.azooKeyMac.setting.action.resetLearningData",
                title: "履歴学習データをリセット",
                section: "履歴学習",
                kind: .button(action: "resetLearningData")
            ),
            descriptor(
                key: Config.InputStyle.key,
                title: "入力方式",
                section: "入力方式",
                kind: .custom(surface: "inputStyle")
            ),
            descriptor(
                key: Config.KeyboardLayout.key,
                title: "キーボード配列",
                section: "キーボード配列",
                kind: .selector(options: [
                    .init(title: "QWERTY", value: .string(Config.KeyboardLayout.Value.qwerty.rawValue)),
                    .init(title: "Australian", value: .string(Config.KeyboardLayout.Value.australian.rawValue)),
                    .init(title: "British", value: .string(Config.KeyboardLayout.Value.british.rawValue)),
                    .init(title: "Colemak", value: .string(Config.KeyboardLayout.Value.colemak.rawValue)),
                    .init(title: "Dvorak", value: .string(Config.KeyboardLayout.Value.dvorak.rawValue)),
                    .init(title: "Dvorak - QWERTY Command", value: .string(Config.KeyboardLayout.Value.dvorakQwertyCommand.rawValue))
                ]),
                value: .string(Config.KeyboardLayout().value.rawValue)
            ),
            descriptor(
                key: Config.ZenzaiProfile.key,
                title: "変換プロフィール",
                section: "変換設定",
                kind: .textField(secure: false),
                value: .string(Config.ZenzaiProfile().value)
            ),
            descriptor(
                key: Config.ZenzaiInferenceLimit.key,
                title: "Zenzaiの推論上限",
                section: "変換設定",
                kind: .number(min: 1, max: 50, step: 1),
                value: .int(Config.ZenzaiInferenceLimit().value)
            ),
            descriptor(
                key: Config.ZenzaiPersonalizationLevel.key,
                title: "パーソナライズ",
                section: "開発者向け設定",
                kind: .selector(options: [
                    .init(title: "オフ", value: .string(Config.ZenzaiPersonalizationLevel.Value.off.rawValue)),
                    .init(title: "弱く", value: .string(Config.ZenzaiPersonalizationLevel.Value.soft.rawValue)),
                    .init(title: "普通", value: .string(Config.ZenzaiPersonalizationLevel.Value.normal.rawValue)),
                    .init(title: "強く", value: .string(Config.ZenzaiPersonalizationLevel.Value.hard.rawValue))
                ]),
                value: .string(Config.ZenzaiPersonalizationLevel().value.rawValue)
            ),
            descriptor(
                key: Config.DebugPredictiveTyping.key,
                title: "開発中の予測入力を有効化",
                section: "開発者向け設定",
                kind: .toggle,
                value: .bool(Config.DebugPredictiveTyping().value)
            ),
            descriptor(
                key: Config.DebugTypoCorrection.key,
                title: "開発中の入力訂正を有効化",
                section: "開発者向け設定",
                kind: .toggle,
                value: .bool(Config.DebugTypoCorrection().value)
            ),
            descriptor(
                key: "dev.ensan.inputmethod.azooKeyMac.setting.action.downloadDebugTypoCorrectionWeights",
                title: "入力訂正の重みをダウンロード",
                section: "開発者向け設定",
                kind: .button(action: "downloadDebugTypoCorrectionWeights")
            ),
            descriptor(
                key: Config.UserDictionary.key,
                title: "ユーザー辞書",
                section: "辞書設定",
                kind: .custom(surface: "userDictionary")
            ),
            descriptor(
                key: Config.SystemUserDictionary.key,
                title: "システム辞書",
                section: "辞書設定",
                kind: .custom(surface: "systemUserDictionary")
            ),
            descriptor(
                key: "dev.ensan.inputmethod.azooKeyMac.setting.surface.foundationModelsAvailability",
                title: "Foundation Models availability",
                section: "基本",
                kind: .custom(surface: "foundationModelsAvailability")
            ),
            descriptor(
                key: Config.OpenAiModelName.key,
                title: "OpenAIモデル名",
                section: "OpenAI API",
                kind: .textField(secure: false),
                value: .string(Config.OpenAiModelName().value.isEmpty ? Config.OpenAiModelName.default : Config.OpenAiModelName().value)
            ),
            descriptor(
                key: Config.OpenAiApiEndpoint.key,
                title: "OpenAI APIエンドポイント",
                section: "OpenAI API",
                kind: .textField(secure: false),
                value: .string(Config.OpenAiApiEndpoint().value)
            ),
            descriptor(
                key: "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiApiKey",
                title: "OpenAI APIキー",
                section: "OpenAI API",
                kind: .textField(secure: true)
            )
        ]
    }

    private static func requiresClientUpdate(
        kind: ConverterSettingKind,
        capabilities: ConverterSettingClientCapabilities
    ) -> Bool {
        guard capabilities.supportedKinds.contains(kind.identifier) else {
            return true
        }
        switch kind {
        case .button(let action):
            return !capabilities.supportedActions.contains(action)
        case .custom(let surface):
            return !capabilities.supportedCustomSurfaces.contains(surface)
        case .toggle, .selector, .textField, .number:
            return false
        }
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    private static func updateSetting(key: String, value: ConverterSettingValue) throws {
        switch key {
        case Config.AIBackendPreference.key:
            guard case .string(let rawValue) = value,
                  let backend = Config.AIBackendPreference.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.AIBackendPreference().value = backend
        case Config.LiveConversion.key:
            Config.LiveConversion().value = try boolSettingValue(value, key: key)
        case Config.TypeBackSlash.key:
            Config.TypeBackSlash().value = try boolSettingValue(value, key: key)
        case Config.TypeHalfSpace.key:
            Config.TypeHalfSpace().value = try boolSettingValue(value, key: key)
        case Config.OptionDirectFullWidthInput.key:
            Config.OptionDirectFullWidthInput().value = try boolSettingValue(value, key: key)
        case Config.PunctuationStyle.key:
            guard case .int(let rawValue) = value,
                  let punctuationStyle = Config.PunctuationStyle.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.PunctuationStyle().value = punctuationStyle
        case Config.Learning.key:
            guard case .string(let rawValue) = value,
                  let learning = Config.Learning.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.Learning().value = learning
        case Config.KeyboardLayout.key:
            guard case .string(let rawValue) = value,
                  let layout = Config.KeyboardLayout.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.KeyboardLayout().value = layout
        case Config.ZenzaiProfile.key:
            guard case .string(let value) = value else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.ZenzaiProfile().value = value
        case Config.ZenzaiInferenceLimit.key:
            guard case .int(let value) = value, (1 ... 50).contains(value) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.ZenzaiInferenceLimit().value = value
        case Config.ZenzaiPersonalizationLevel.key:
            guard case .string(let rawValue) = value,
                  let level = Config.ZenzaiPersonalizationLevel.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.ZenzaiPersonalizationLevel().value = level
        case Config.DebugPredictiveTyping.key:
            Config.DebugPredictiveTyping().value = try boolSettingValue(value, key: key)
        case Config.DebugTypoCorrection.key:
            Config.DebugTypoCorrection().value = try boolSettingValue(value, key: key)
        case Config.OpenAiModelName.key:
            guard case .string(let value) = value else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.OpenAiModelName().value = value
        case Config.OpenAiApiEndpoint.key:
            guard case .string(let value) = value else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.OpenAiApiEndpoint().value = value
        default:
            throw ConverterServerError.unknownSetting(key)
        }
    }

    private static func boolSettingValue(_ value: ConverterSettingValue, key: String) throws -> Bool {
        guard case .bool(let boolValue) = value else {
            throw ConverterServerError.invalidSettingValue(key)
        }
        return boolValue
    }

    private static func scheduleShutdown() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exit(EXIT_SUCCESS)
        }
    }

    @MainActor
    private func getSession(_ sessionID: String) throws -> ConverterSession {
        guard let session = sessions[sessionID] else {
            throw ConverterServerError.unknownSession(sessionID)
        }
        return session
    }

    @MainActor
    private func makeResponse(
        for session: ConverterSession,
        inputState: InputState,
        handled: Bool = true,
        effects: [ConverterClientEffect] = [],
        settings: [ConverterSettingDescriptor] = [],
        responseInputState: ConverterInputState? = nil
    ) -> ConverterServerResponse {
        ConverterServerResponse(
            handled: handled,
            effects: effects,
            inputState: responseInputState ?? ConverterInputState(inputState),
            settings: settings,
            snapshot: snapshot(for: session, inputState: inputState)
        )
    }

    @MainActor
    private func snapshot(for session: ConverterSession, inputState: InputState) -> ConverterSessionSnapshot {
        let manager = session.manager
        if manager.isEmpty {
            return .empty
        }
        let markedText: ConverterMarkedText
        if inputState == .replaceSuggestion, let candidate = session.selectedReplaceSuggestion {
            markedText = ConverterMarkedText(
                elements: [.init(content: candidate.text, focus: .focused)],
                selectionRange: .init(location: candidate.text.count, length: 0)
            )
        } else {
            markedText = ConverterMarkedText(manager.getCurrentMarkedText(inputState: inputState))
        }
        let candidateWindow: ConverterCandidateWindow
        switch manager.getCurrentCandidateWindow(inputState: inputState) {
        case .hidden:
            candidateWindow = .hidden
        case .composing(let candidates, let selectionIndex):
            candidateWindow = .composing(
                manager.makeCandidatePresentations(candidates).map(ConverterCandidatePresentation.init),
                selectionIndex: selectionIndex
            )
        case .selecting(let candidates, let selectionIndex):
            candidateWindow = .selecting(
                manager.makeCandidatePresentations(candidates).map(ConverterCandidatePresentation.init),
                selectionIndex: selectionIndex
            )
        }
        let predictionCandidates: [ConverterPredictionCandidate]
        if inputState == .composing {
            predictionCandidates = SegmentsManager.preferredPredictionCandidates(
                typoCorrectionCandidates: manager.requestTypoCorrectionPredictionCandidates(),
                predictionCandidates: manager.requestPredictionCandidates()
            ).map(ConverterPredictionCandidate.init)
        } else {
            predictionCandidates = []
        }
        return ConverterSessionSnapshot(
            markedText: markedText,
            candidateWindow: candidateWindow,
            predictionCandidates: predictionCandidates,
            replaceSuggestionCandidates: session.replaceSuggestions.map {
                ConverterCandidatePresentation(CandidatePresentation(candidate: $0))
            },
            replaceSuggestionSelectionIndex: session.replaceSuggestionSelectionIndex,
            isEmpty: manager.isEmpty,
            convertTarget: manager.convertTarget
        )
    }

    @MainActor
    private static func makeSegmentsManager() -> SegmentsManager {
        CustomInputTableStore.registerIfExists()
        let containerURL = AppGroup.containerURL()
        return SegmentsManager(
            kanaKanjiConverter: KanaKanjiConverter.withDefaultDictionary(),
            applicationDirectoryURL: AppGroup.memoryDirectoryURL(),
            containerURL: containerURL,
            context: .init(useZenzai: true, resourcesDirectoryURL: appResourcesDirectoryURL())
        )
    }

    private static func appResourcesDirectoryURL() -> URL {
        if let executableURL = Bundle.main.executableURL {
            return executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
        }
        if let resourceURL = Bundle.main.resourceURL {
            return resourceURL
        }
        return Bundle.main.bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    }

    @MainActor
    private static func resolveInputStyle(_ inputStyle: ConverterInputStyle) -> InputStyle {
        if case .tableName(CustomInputTableStore.tableName) = inputStyle,
           !CustomInputTableStore.registerIfExists() {
            return .mapped(id: .defaultRomanToKana)
        }
        return inputStyle.inputStyle
    }

    @MainActor
    private static func transformedCandidate(
        _ transform: ConverterCandidateTransform,
        manager: SegmentsManager,
        inputState: InputState
    ) -> Candidate {
        switch transform {
        case .hiragana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toHiragana()
            }
        case .katakana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toKatakana()
            }
        case .halfWidthKatakana:
            manager.getModifiedRubyCandidate(inputState: inputState) {
                $0.toKatakana().applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            }
        case .fullWidthRoman:
            manager.getModifiedRomanCandidate(inputState: inputState) {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: true)!
            }
        case .halfWidthRoman:
            manager.getModifiedRomanCandidate(inputState: inputState) {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            }
        }
    }
}

private enum ConverterServerError: LocalizedError {
    case unknownSession(String)
    case unknownSetting(String)
    case invalidSettingValue(String)

    var errorDescription: String? {
        switch self {
        case .unknownSession(let sessionID):
            "Unknown converter session: \(sessionID)"
        case .unknownSetting(let key):
            "Unknown converter setting: \(key)"
        case .invalidSettingValue(let key):
            "Invalid converter setting value: \(key)"
        }
    }
}

private final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let server = ConverterServer()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ConverterServerXPCProtocol.self)
        connection.exportedObject = server
        connection.resume()
        return true
    }
}

let listener = NSXPCListener(machServiceName: ConverterServerXPC.machServiceName)
private let delegate = ServiceDelegate()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
