import InputMethodKit

public enum InputState: Sendable, Hashable {
    case none
    case composing
    case previewing
    case selecting
    case replaceSuggestion

    public struct EventCore: Sendable, Equatable {
        public init(modifierFlags: NSEvent.ModifierFlags) {
            self.modifierFlags = modifierFlags
        }
        var modifierFlags: NSEvent.ModifierFlags
    }

    public func event(  // swiftlint:disable:this function_parameter_count
        _ event: NSEvent!,
        userAction: UserAction,
        inputLanguage: InputLanguage,
        liveConversionEnabled: Bool,
        enableDebugWindow: Bool,
        enableSuggestion: Bool
    ) -> (ClientAction, ClientActionCallback) {
        self.event(
            eventCore: EventCore(modifierFlags: event.modifierFlags),
            userAction: userAction,
            inputLanguage: inputLanguage,
            liveConversionEnabled: liveConversionEnabled,
            enableDebugWindow: enableDebugWindow,
            enableSuggestion: enableSuggestion
        )
    }

    // この種のコードは複雑にしかならないので、lintを無効にする
    // swiftlint:disable:next cyclomatic_complexity
    public func event(  // swiftlint:disable:this function_parameter_count
        eventCore event: EventCore,
        userAction: UserAction,
        inputLanguage: InputLanguage,
        liveConversionEnabled: Bool,
        enableDebugWindow: Bool,
        enableSuggestion: Bool
    ) -> (ClientAction, ClientActionCallback) {
        if event.modifierFlags.contains(.command) {
            return (.fallthrough, .fallthrough)
        }
        if event.modifierFlags.contains(.option) {
            guard case .input = userAction else {
                return (.fallthrough, .fallthrough)
            }
        }
        switch self {
        case .none:
            switch userAction {
            case .input(let string):
                switch inputLanguage {
                case .japanese:
                    return (.appendToMarkedText(string), .transition(.composing))
                case .english:
                    return (.insertWithoutMarkedText(string), .fallthrough)
                }
            case .number(let number):
                switch inputLanguage {
                case .japanese:
                    return (.appendToMarkedText(number.inputString), .transition(.composing))
                case .english:
                    return (.insertWithoutMarkedText(number.inputString), .fallthrough)
                }
            case .かな:
                return (.selectInputLanguage(.japanese), .fallthrough)
            case .英数:
                return (.selectInputLanguage(.english), .fallthrough)
            case .space(let isFullSpace):
                if inputLanguage != .english && isFullSpace {
                    return (.insertWithoutMarkedText("　"), .fallthrough)
                } else {
                    return (.insertWithoutMarkedText(" "), .fallthrough)
                }
            case .suggest:
                if enableSuggestion {
                    return (.requestPredictiveSuggestion, .transition(.replaceSuggestion))
                } else {
                    return (.fallthrough, .fallthrough)
                }
            case .unknown, .navigation, .backspace, .enter, .escape, .function, .editSegment, .tab:
                return (.fallthrough, .fallthrough)
            }
        case .composing:
            switch userAction {
            case .input(let string):
                return (.appendToMarkedText(string), .fallthrough)
            case .number(let number):
                return (.appendToMarkedText(number.inputString), .fallthrough)
            case .backspace:
                return (.removeLastMarkedText, .basedOnBackspace(ifIsEmpty: .none, ifIsNotEmpty: .composing))
            case .enter:
                return (.commitMarkedText, .transition(.none))
            case .escape:
                return (.stopComposition, .transition(.none))
            case .space:
                if liveConversionEnabled {
                    return (.enterCandidateSelectionMode, .transition(.selecting))
                } else {
                    return (.enterFirstCandidatePreviewMode, .transition(.previewing))
                }
            case let .function(function):
                switch function {
                case .six:
                    return (.submitHiraganaCandidate, .transition(.none))
                case .seven:
                    return (.submitKatakanaCandidate, .transition(.none))
                case .eight:
                    return (.submitHankakuKatakanaCandidate, .transition(.none))
                }
            case .かな:
                return (.consume, .fallthrough)
            case .英数:
                return (.commitMarkedTextAndSelectInputLanguage(.english), .transition(.none))
            case .navigation(let direction):
                if direction == .down {
                    return (.enterCandidateSelectionMode, .transition(.selecting))
                } else if direction == .right && event.modifierFlags.contains(.shift) {
                    return (.editSegment(1), .transition(.selecting))
                } else if direction == .left && event.modifierFlags.contains(.shift) {
                    return (.editSegment(-1), .transition(.selecting))
                } else {
                    // ナビゲーションはハンドルしてしまう
                    return (.consume, .fallthrough)
                }
            case .editSegment(let count):
                return (.editSegment(count), .transition(.selecting))
            case .suggest:
                if enableSuggestion {
                    return (.requestReplaceSuggestion, .transition(.replaceSuggestion))
                } else {
                    return (.fallthrough, .fallthrough)
                }
            case .unknown, .tab:
                return (.fallthrough, .fallthrough)
            }
        case .previewing:
            switch userAction {
            case .input(let string):
                return (.commitMarkedTextAndAppendToMarkedText(string), .transition(.composing))
            case .number(let number):
                return (.appendToMarkedText(number.inputString), .transition(.composing))
            case .backspace:
                return (.removeLastMarkedText, .transition(.composing))
            case .enter:
                return (.commitMarkedText, .transition(.none))
            case .space:
                return (.enterCandidateSelectionMode, .transition(.selecting))
            case .escape:
                return (.hideCandidateWindow, .transition(.composing))
            case let .function(function):
                switch function {
                case .six:
                    return (.submitHiraganaCandidate, .transition(.none))
                case .seven:
                    return (.submitKatakanaCandidate, .transition(.none))
                case .eight:
                    return (.submitHankakuKatakanaCandidate, .transition(.none))
                }
            case .かな:
                return (.consume, .fallthrough)
            case .英数:
                return (.commitMarkedTextAndSelectInputLanguage(.english), .transition(.none))
            case .navigation(let direction):
                if direction == .down {
                    return (.enterCandidateSelectionMode, .transition(.selecting))
                } else if direction == .right && event.modifierFlags.contains(.shift) {
                    return (.editSegment(1), .transition(.selecting))
                } else if direction == .left && event.modifierFlags.contains(.shift) {
                    return (.editSegment(-1), .transition(.selecting))
                } else {
                    // ナビゲーションはハンドルしてしまう
                    return (.consume, .fallthrough)
                }
            case .editSegment(let count):
                return (.editSegment(count), .transition(.selecting))
            case .unknown, .suggest, .tab:
                return (.fallthrough, .fallthrough)
            }
        case .selecting:
            switch userAction {
            case .input(let string):
                if string == "d" && enableDebugWindow {
                    return (.enableDebugWindow, .fallthrough)
                } else if string == "D" && enableDebugWindow {
                    return (.disableDebugWindow, .fallthrough)
                }
                return (.commitMarkedTextAndAppendToMarkedText(string), .transition(.composing))
            case .enter:
                return (.submitSelectedCandidate, .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .previewing))
            case .backspace:
                return (.removeLastMarkedText, .basedOnBackspace(ifIsEmpty: .none, ifIsNotEmpty: .composing))
            case .escape:
                if liveConversionEnabled {
                    return (.hideCandidateWindow, .transition(.composing))
                } else {
                    return (.enterFirstCandidatePreviewMode, .transition(.previewing))
                }
            case .space:
                // シフトが入っている場合は上に移動する
                if event.modifierFlags.contains(.shift) {
                    return (.selectPrevCandidate, .fallthrough)
                } else {
                    return (.selectNextCandidate, .fallthrough)
                }
            case .navigation(let direction):
                if direction == .right {
                    if event.modifierFlags.contains(.shift) {
                        return (.editSegment(1), .fallthrough)
                    } else {
                        return (.submitSelectedCandidate, .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .selecting))
                    }
                } else if direction == .left && event.modifierFlags.contains(.shift) {
                    return (.editSegment(-1), .fallthrough)
                } else if direction == .down {
                    return (.selectNextCandidate, .fallthrough)
                } else if direction == .up {
                    return (.selectPrevCandidate, .fallthrough)
                } else {
                    return (.consume, .fallthrough)
                }
            case let .function(function):
                switch function {
                case .six:
                    return (.submitHiraganaCandidate, .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .selecting))
                case .seven:
                    return (.submitKatakanaCandidate, .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .selecting))
                case .eight:
                    return (.submitHankakuKatakanaCandidate, .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .selecting))
                }
            case .number(let num):
                switch num {
                case .one, .two, .three, .four, .five, .six, .seven, .eight, .nine:
                    return (.selectNumberCandidate(num.intValue), .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .previewing))
                case .zero:
                    return (.submitSelectedCandidateAndAppendToMarkedText(num.inputString), .transition(.composing))
                }
            case .editSegment(let count):
                return (.editSegment(count), .transition(.selecting))
            case .かな:
                return (.consume, .fallthrough)
            case .英数:
                return (.commitMarkedTextAndSelectInputLanguage(.english), .transition(.none))
            case .unknown, .suggest, .tab:
                return (.fallthrough, .fallthrough)
            }
        case .replaceSuggestion:
            switch userAction {
            // 入力があったらcomposingに戻る
            case .input(let string):
                return (.appendToMarkedText(string), .transition(.composing))
            case .space:
                return (.selectNextReplaceSuggestionCandidate, .fallthrough)
            case .navigation(let direction):
                if direction == .down {
                    return (.selectNextReplaceSuggestionCandidate, .fallthrough)
                } else if direction == .up {
                    return (.selectPrevReplaceSuggestionCandidate, .fallthrough)
                } else {
                    return (.consume, .fallthrough)
                }
            case .suggest:
                return (.requestReplaceSuggestion, .fallthrough)
            case .enter:
                return (.submitReplaceSuggestionCandidate, .transition(.none))
            case .backspace, .escape:
                return (.hideReplaceSuggestionWindow, .transition(.composing))
            case .英数:
                return (.submitReplaceSuggestionCandidate, .transition(.none))
            default:
                return (.fallthrough, .fallthrough)
            }
        }
    }
}
