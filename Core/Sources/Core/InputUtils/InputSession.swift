import Foundation
import KanaKanjiConverterModule

/// Owns the synchronous input state and composition used by an input-method client.
///
/// Platform adapters translate native key events into ``KeyEventCore`` and apply
/// the returned effects to their text client and windows.
public final class InputSession {
    public struct Configuration {
        public var inputStyle: InputStyle
        public var liveConversionEnabled: Bool
        public var enableDebugWindow: Bool
        public var enableSuggestion: Bool

        public init(
            inputStyle: InputStyle,
            liveConversionEnabled: Bool,
            enableDebugWindow: Bool,
            enableSuggestion: Bool
        ) {
            self.inputStyle = inputStyle
            self.liveConversionEnabled = liveConversionEnabled
            self.enableDebugWindow = enableDebugWindow
            self.enableSuggestion = enableSuggestion
        }
    }

    public enum Effect {
        case insertText(String)
        case selectInputLanguage(InputLanguage)
        case selectNextReplaceSuggestionCandidate
        case selectPrevReplaceSuggestionCandidate
        case submitReplaceSuggestionCandidate
        case hideReplaceSuggestionWindow
        case requestReplaceSuggestion
        case showPromptInputWindow
        case transformSelectedText(String, String)
    }

    public struct Result {
        public var handled: Bool
        public var effects: [Effect]

        public init(handled: Bool, effects: [Effect] = []) {
            self.handled = handled
            self.effects = effects
        }
    }

    public let segmentsManager: SegmentsManager
    public private(set) var inputState: InputState
    public private(set) var inputLanguage: InputLanguage

    public init(
        segmentsManager: SegmentsManager,
        inputState: InputState = .none,
        inputLanguage: InputLanguage = .japanese
    ) {
        self.segmentsManager = segmentsManager
        self.inputState = inputState
        self.inputLanguage = inputLanguage
    }

    @MainActor
    public func handle(
        eventCore: KeyEventCore,
        userAction: UserAction,
        configuration: Configuration,
        numberCandidateIndex: (Int) -> Int = { $0 - 1 }
    ) -> Result {
        let (clientAction, callback) = self.inputState.event(
            eventCore: eventCore,
            userAction: userAction,
            inputLanguage: self.inputLanguage,
            liveConversionEnabled: configuration.liveConversionEnabled,
            enableDebugWindow: configuration.enableDebugWindow,
            enableSuggestion: configuration.enableSuggestion
        )
        return self.handle(
            clientAction,
            callback: callback,
            inputStyle: configuration.inputStyle,
            numberCandidateIndex: numberCandidateIndex
        )
    }

    // This switch intentionally mirrors every ClientAction so platform clients
    // cannot accidentally fall back after a new synchronous action is added.
    // swiftlint:disable cyclomatic_complexity
    @MainActor
    public func handle(
        _ clientAction: ClientAction,
        callback: ClientActionCallback,
        inputStyle: InputStyle,
        numberCandidateIndex: (Int) -> Int = { $0 - 1 }
    ) -> Result {
        var effects: [Effect] = []
        switch clientAction {
        case .showCandidateWindow:
            self.segmentsManager.requestSetCandidateWindowState(visible: true)
        case .hideCandidateWindow:
            self.segmentsManager.requestSetCandidateWindowState(visible: false)
        case .enterFirstCandidatePreviewMode:
            self.segmentsManager.insertCompositionSeparator(inputStyle: inputStyle, skipUpdate: false)
            self.segmentsManager.requestSetCandidateWindowState(visible: false)
        case .enterCandidateSelectionMode:
            self.segmentsManager.insertCompositionSeparator(inputStyle: inputStyle, skipUpdate: true)
            self.segmentsManager.update(requestRichCandidates: true)
        case .appendToMarkedText(let string):
            self.segmentsManager.insertAtCursorPosition(string, inputStyle: self.compositionInputStyle(inputStyle))
        case .appendPieceToMarkedText(let pieces):
            self.segmentsManager.insertAtCursorPosition(pieces: pieces, inputStyle: self.compositionInputStyle(inputStyle))
        case .insertWithoutMarkedText(let string):
            effects.append(.insertText(string))
        case .editSegment(let count):
            self.segmentsManager.editSegment(count: count)
        case .commitMarkedText:
            effects.append(.insertText(self.segmentsManager.commitMarkedText(inputState: self.inputState)))
        case .commitMarkedTextAndAppendToMarkedText(let string):
            effects.append(.insertText(self.segmentsManager.commitMarkedText(inputState: self.inputState)))
            self.segmentsManager.insertAtCursorPosition(string, inputStyle: self.compositionInputStyle(inputStyle))
        case .commitMarkedTextAndAppendPieceToMarkedText(let pieces):
            effects.append(.insertText(self.segmentsManager.commitMarkedText(inputState: self.inputState)))
            self.segmentsManager.insertAtCursorPosition(pieces: pieces, inputStyle: self.compositionInputStyle(inputStyle))
        case .submitSelectedCandidate:
            effects += self.submitSelectedCandidate()
        case .removeLastMarkedText:
            self.segmentsManager.deleteBackwardFromCursorPosition()
            self.segmentsManager.requestResettingSelection()
        case .selectPrevCandidate:
            self.segmentsManager.requestSelectingPrevCandidate()
        case .selectNextCandidate:
            self.segmentsManager.requestSelectingNextCandidate()
        case .selectNumberCandidate(let number):
            self.segmentsManager.requestSelectingRow(numberCandidateIndex(number))
            effects += self.submitSelectedCandidate()
        case .submitHiraganaCandidate:
            effects += self.submitCandidate(self.segmentsManager.getModifiedRubyCandidate(inputState: self.inputState) {
                $0.toHiragana()
            })
        case .submitKatakanaCandidate:
            effects += self.submitCandidate(self.segmentsManager.getModifiedRubyCandidate(inputState: self.inputState) {
                $0.toKatakana()
            })
        case .submitHankakuKatakanaCandidate:
            effects += self.submitCandidate(self.segmentsManager.getModifiedRubyCandidate(inputState: self.inputState) {
                $0.toKatakana().applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            })
        case .submitFullWidthRomanCandidate:
            effects += self.submitCandidate(self.segmentsManager.getModifiedRomanCandidate {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: true)!
            })
        case .submitHalfWidthRomanCandidate:
            effects += self.submitCandidate(self.segmentsManager.getModifiedRomanCandidate {
                $0.applyingTransform(.fullwidthToHalfwidth, reverse: false)!
            })
        case .enableDebugWindow:
            self.segmentsManager.requestDebugWindowMode(enabled: true)
        case .disableDebugWindow:
            self.segmentsManager.requestDebugWindowMode(enabled: false)
        case .stopComposition:
            self.segmentsManager.stopComposition()
        case .forgetMemory:
            self.segmentsManager.forgetMemory()
        case .selectInputLanguage(let language):
            effects += self.selectInputLanguage(language)
        case .commitMarkedTextAndSelectInputLanguage(let language):
            effects.append(.insertText(self.segmentsManager.commitMarkedText(inputState: self.inputState)))
            effects += self.selectInputLanguage(language)
        case .requestPredictiveSuggestion:
            self.segmentsManager.insertAtCursorPosition("つづき", inputStyle: inputStyle)
            effects.append(.requestReplaceSuggestion)
        case .acceptPredictionCandidate:
            self.acceptPredictionCandidate()
        case .requestReplaceSuggestion:
            effects.append(.requestReplaceSuggestion)
        case .selectNextReplaceSuggestionCandidate:
            effects.append(.selectNextReplaceSuggestionCandidate)
        case .selectPrevReplaceSuggestionCandidate:
            effects.append(.selectPrevReplaceSuggestionCandidate)
        case .submitReplaceSuggestionCandidate:
            effects.append(.submitReplaceSuggestionCandidate)
        case .hideReplaceSuggestionWindow:
            effects.append(.hideReplaceSuggestionWindow)
        case .showPromptInputWindow:
            self.segmentsManager.appendDebugMessage("Executing showPromptInputWindow")
            effects.append(.showPromptInputWindow)
        case .transformSelectedText(let selectedText, let prompt):
            self.segmentsManager.appendDebugMessage("Executing transformSelectedText with text: '\(selectedText)' and prompt: '\(prompt)'")
            effects.append(.transformSelectedText(selectedText, prompt))
        case .enterUnicodeInputMode, .appendToUnicodeInput, .removeLastUnicodeInput, .cancelUnicodeInput, .consume:
            break
        case .submitUnicodeInput(let codePoint):
            if let scalar = UInt32(codePoint, radix: 16), let unicodeScalar = Unicode.Scalar(scalar) {
                effects.append(.insertText(String(Character(unicodeScalar))))
            }
        case .submitSelectedCandidateAndEnterUnicodeInputMode:
            effects += self.submitSelectedCandidate()
            if !self.segmentsManager.isEmpty {
                effects.append(.insertText(self.segmentsManager.convertTarget))
                self.segmentsManager.stopComposition()
            }
        case .fallthrough:
            return Result(handled: false)
        }

        effects += self.apply(callback)
        return Result(handled: true, effects: effects)
    }
    // swiftlint:enable cyclomatic_complexity

    @MainActor
    public func commitComposition() -> Result {
        if case .unicodeInput = self.inputState {
            self.inputState = .none
            return Result(handled: true)
        }
        guard !self.segmentsManager.isEmpty else {
            return Result(handled: false)
        }
        let text = self.segmentsManager.commitMarkedText(inputState: self.inputState)
        self.inputState = .none
        return Result(handled: true, effects: [.insertText(text)])
    }

    @MainActor
    public func synchronizeInputLanguage(_ language: InputLanguage) {
        self.inputLanguage = language
        if language == .english {
            self.segmentsManager.stopJapaneseInput()
        }
    }

    @MainActor
    public func submitCandidate(_ candidate: Candidate) -> [Effect] {
        let leftSideContext = self.segmentsManager.getCleanLeftSideContext(maxCount: 30) ?? ""
        self.segmentsManager.prefixCandidateCommited(candidate, leftSideContext: leftSideContext)
        return [.insertText(candidate.text)]
    }

    @MainActor
    public func submitSelectedCandidate() -> [Effect] {
        guard let candidate = self.segmentsManager.selectedCandidate else {
            return []
        }
        let effects = self.submitCandidate(candidate)
        self.segmentsManager.requestResettingSelection()
        return effects
    }

    private func compositionInputStyle(_ inputStyle: InputStyle) -> InputStyle {
        self.inputLanguage == .english ? .direct : inputStyle
    }

    @MainActor
    private func selectInputLanguage(_ language: InputLanguage) -> [Effect] {
        self.synchronizeInputLanguage(language)
        return [.selectInputLanguage(language)]
    }

    @MainActor
    private func apply(_ callback: ClientActionCallback) -> [Effect] {
        switch callback {
        case .fallthrough:
            return []
        case .transition(let inputState):
            var effects: [Effect] = []
            if inputState != .replaceSuggestion {
                effects.append(.hideReplaceSuggestionWindow)
            }
            if inputState == .none {
                effects += self.selectInputLanguage(self.inputLanguage)
            }
            self.inputState = inputState
            return effects
        case .basedOnBackspace(let ifIsEmpty, let ifIsNotEmpty),
             .basedOnSubmitCandidate(let ifIsEmpty, let ifIsNotEmpty):
            self.inputState = self.segmentsManager.isEmpty ? ifIsEmpty : ifIsNotEmpty
            return []
        }
    }

    @MainActor
    private func acceptPredictionCandidate() {
        let predictions = SegmentsManager.preferredPredictionCandidates(
            typoCorrectionCandidates: self.segmentsManager.requestTypoCorrectionPredictionCandidates(),
            predictionCandidates: self.segmentsManager.requestPredictionCandidates()
        )
        guard let prediction = predictions.first else {
            return
        }
        if prediction.deleteCount > 0 {
            self.segmentsManager.deleteBackwardFromCursorPosition(count: prediction.deleteCount)
        }
        guard !prediction.appendText.isEmpty else {
            return
        }
        self.segmentsManager.insertAtCursorPosition(prediction.appendText, inputStyle: .direct)
    }
}
