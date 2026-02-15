import Foundation
import KanaKanjiConverterModule

public enum InputState: Sendable, Hashable {
    case none
    case attachDiacritic(String)
    case composing
    case previewing
    case selecting
    case replaceSuggestion
    case unicodeInput(String)

    // この種のコードは複雑にしかならないので、lintを無効にする
    // swiftlint:disable:next cyclomatic_complexity
    public func event(  // swiftlint:disable:this function_parameter_count
        eventCore event: KeyEventCore,
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
            switch userAction {
            case .input, .deadKey, .backspace:
                break
            case .enter where self == .composing:
                break
            case .tab where self == .composing || self == .previewing || self == .selecting || self == .replaceSuggestion:
                break
            case .navigation(let direction) where self == .composing || self == .previewing || self == .selecting || self == .replaceSuggestion:
                switch direction {
                case .up, .down, .left, .right:
                    return (.consume, .fallthrough)
                }
            case .escape where self == .composing || self == .previewing || self == .selecting || self == .replaceSuggestion:
                return (.consume, .fallthrough)
            case .英数 where self == .composing || self == .previewing || self == .selecting || self == .replaceSuggestion:
                return (.consume, .fallthrough)
            case .かな where self == .composing || self == .previewing || self == .selecting || self == .replaceSuggestion:
                return (.consume, .fallthrough)
            default:
                return (.fallthrough, .fallthrough)
            }
        }
        switch self {
        case .none:
            switch userAction {
            case .input(let string):
                switch inputLanguage {
                case .japanese:
                    return (.appendPieceToMarkedText(string), .transition(.composing))
                case .english:
                    // 連結する
                    return (.insertWithoutMarkedText(string.inputString(preferIntention: true)), .fallthrough)
                }
            case .deadKey(let diacritic):
                if inputLanguage == .english {
                    return (.consume, .transition(.attachDiacritic(diacritic)))
                } else {
                    return (.fallthrough, .fallthrough)
                }
            case .number(let number):
                switch inputLanguage {
                case .japanese:
                    return (.appendPieceToMarkedText([number.inputPiece]), .transition(.composing))
                case .english:
                    return (.insertWithoutMarkedText(number.inputString), .fallthrough)
                }
            case .英数:
                return (.selectInputLanguage(.english), .fallthrough)
            case .かな:
                return (.selectInputLanguage(.japanese), .fallthrough)
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
            case .startUnicodeInput:
                return (.enterUnicodeInputMode, .transition(.unicodeInput("")))
            case .unknown, .navigation, .backspace, .enter, .escape, .function, .editSegment, .tab, .forget, .transformSelectedText:
                return (.fallthrough, .fallthrough)
            }
        case .attachDiacritic(let diacritic):
            switch userAction {
            case .input(let string):
                let string = string.inputString(preferIntention: true)
                if let result = DiacriticAttacher.attach(deadKeyChar: diacritic, with: string, shift: event.modifierFlags.contains(.shift)) {
                    return (.insertWithoutMarkedText(result), .transition(.none))
                } else {
                    return (.insertWithoutMarkedText(diacritic + string), .transition(.none))
                }
            case .deadKey(let newDiacritic):
                return (.insertWithoutMarkedText(diacritic), .transition(.attachDiacritic(newDiacritic)))
            case .number(let number):
                return (.insertWithoutMarkedText(diacritic + number.inputString), .transition(.none))
            case .backspace, .escape:
                return (.stopComposition, .transition(.none))
            case .かな:
                return (.selectInputLanguage(.japanese), .transition(.none))
            case .function:
                return (.consume, .fallthrough)
            case .enter:
                return (.insertWithoutMarkedText(diacritic + "\n"), .transition(.none))
            case .tab:
                return (.insertWithoutMarkedText(diacritic + "\t"), .transition(.none))
            case .startUnicodeInput:
                return (.insertWithoutMarkedText(diacritic), .transition(.unicodeInput("")))
            case .unknown, .space, .英数, .navigation, .editSegment, .suggest, .forget, .transformSelectedText:
                return (.insertWithoutMarkedText(diacritic), .transition(.none))
            }
        case .composing:
            switch userAction {
            case .input(let string):
                return (.appendPieceToMarkedText(string), .fallthrough)
            case .number(let number):
                return (.appendPieceToMarkedText([number.inputPiece]), .fallthrough)
            case .backspace:
                if event.modifierFlags.contains(.option) {
                    return (.consume, .fallthrough)
                } else {
                    return (.removeLastMarkedText, .basedOnBackspace(ifIsEmpty: .none, ifIsNotEmpty: .composing))
                }
            case .enter:
                if event.modifierFlags.contains(.option) {
                    return (.consume, .fallthrough)
                } else {
                    return (.commitMarkedText, .transition(.none))
                }
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
                case .nine:
                    return (.submitFullWidthRomanCandidate, .transition(.none))
                case .ten:
                    return (.submitHalfWidthRomanCandidate, .transition(.none))
                }
            case .forget:
                return (.consume, .fallthrough)
            case .tab:
                if event.modifierFlags.contains(.option) {
                    return (.consume, .fallthrough)
                } else {
                    return (.acceptPredictionCandidate, .fallthrough)
                }
            case .英数:
                return (.selectInputLanguage(.english), .fallthrough)
            case .かな:
                return (.selectInputLanguage(.japanese), .fallthrough)
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
            case .startUnicodeInput:
                return (.commitMarkedText, .transition(.unicodeInput("")))
            case .unknown, .transformSelectedText, .deadKey:
                return (.fallthrough, .fallthrough)
            }
        case .previewing:
            switch userAction {
            case .input(let string):
                return (.commitMarkedTextAndAppendPieceToMarkedText(string), .transition(.composing))
            case .number(let number):
                return (.commitMarkedTextAndAppendPieceToMarkedText([number.inputPiece]), .transition(.composing))
            case .backspace:
                if event.modifierFlags.contains(.option) {
                    return (.consume, .fallthrough)
                } else {
                    return (.removeLastMarkedText, .transition(.composing))
                }
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
                case .nine:
                    return (.submitFullWidthRomanCandidate, .transition(.none))
                case .ten:
                    return (.submitHalfWidthRomanCandidate, .transition(.none))
                }
            case .英数:
                return (.selectInputLanguage(.english), .fallthrough)
            case .かな:
                return (.selectInputLanguage(.japanese), .fallthrough)
            case .forget, .tab:
                return (.consume, .fallthrough)
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
            case .startUnicodeInput:
                return (.commitMarkedText, .transition(.unicodeInput("")))
            case .unknown, .suggest, .transformSelectedText, .deadKey:
                return (.fallthrough, .fallthrough)
            }
        case .selecting:
            switch userAction {
            case .input(let string):
                let s = string.inputString(preferIntention: true)
                if s == "d" && enableDebugWindow {
                    return (.enableDebugWindow, .fallthrough)
                } else if s == "D" && enableDebugWindow {
                    return (.disableDebugWindow, .fallthrough)
                }
                // FIXME: ここの動作はmacOSの標準と異なる。具体的には、macOSの標準ではselectingをcomposingに戻して入力を継続する動きになる。
                return (.commitMarkedTextAndAppendPieceToMarkedText(string), .transition(.composing))
            case .enter:
                return (.submitSelectedCandidate, .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .previewing))
            case .backspace:
                if event.modifierFlags.contains(.option) {
                    return (.consume, .fallthrough)
                } else {
                    return (.removeLastMarkedText, .basedOnBackspace(ifIsEmpty: .none, ifIsNotEmpty: .composing))
                }
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
                case .nine:
                    return (.submitFullWidthRomanCandidate, .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .selecting))
                case .ten:
                    return (.submitHalfWidthRomanCandidate, .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .selecting))
                }
            case .number(let num):
                switch num {
                case .one, .two, .three, .four, .five, .six, .seven, .eight, .nine:
                    return (.selectNumberCandidate(num.intValue), .basedOnSubmitCandidate(ifIsEmpty: .none, ifIsNotEmpty: .previewing))
                case .zero, .shiftZero:
                    return (.commitMarkedTextAndAppendPieceToMarkedText([num.inputPiece]), .transition(.composing))
                }
            case .editSegment(let count):
                return (.editSegment(count), .transition(.selecting))
            case .forget:
                return (.forgetMemory, .fallthrough)
            case .英数:
                // このケースでは確定して英数入力を始める
                // FIXME: ここの動作はmacOSの標準と異なる。具体的には、selectInputLanguage(.english)相当の動作だけが発生する。
                return (.commitMarkedTextAndSelectInputLanguage(.english), .fallthrough)
            case .かな:
                return (.selectInputLanguage(.japanese), .fallthrough)
            case .tab:
                return (.consume, .fallthrough)
            case .startUnicodeInput:
                return (.submitSelectedCandidateAndEnterUnicodeInputMode, .transition(.unicodeInput("")))
            case .unknown, .suggest, .transformSelectedText, .deadKey:
                return (.fallthrough, .fallthrough)
            }
        case .replaceSuggestion:
            switch userAction {
            // 入力があったらcomposingに戻る
            case .input(let string):
                return (.appendPieceToMarkedText(string), .transition(.composing))
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
                return (.selectInputLanguage(.english), .fallthrough)
            case .かな:
                return (.selectInputLanguage(.japanese), .fallthrough)
            case .forget, .tab:
                return (.consume, .fallthrough)
            case .startUnicodeInput:
                return (.hideReplaceSuggestionWindow, .transition(.unicodeInput("")))
            case .unknown, .function, .number, .editSegment, .transformSelectedText, .deadKey:
                return (.fallthrough, .fallthrough)
            }
        case .unicodeInput(let codePoint):
            switch userAction {
            case .input(let pieces):
                let input = pieces.inputString(preferIntention: true).lowercased()
                // 16進数のみ受け付ける
                let hexChars = CharacterSet(charactersIn: "0123456789abcdef")
                let filteredInput = input.unicodeScalars.filter { hexChars.contains($0) }.map { String($0) }.joined()
                if !filteredInput.isEmpty {
                    return (.appendToUnicodeInput(filteredInput), .transition(.unicodeInput(codePoint + filteredInput)))
                } else {
                    return (.consume, .fallthrough)
                }
            case .number(let number):
                let digit = number.inputString
                return (.appendToUnicodeInput(digit), .transition(.unicodeInput(codePoint + digit)))
            case .backspace:
                if codePoint.isEmpty {
                    return (.cancelUnicodeInput, .transition(.none))
                } else {
                    let newCodePoint = String(codePoint.dropLast())
                    return (.removeLastUnicodeInput, .transition(.unicodeInput(newCodePoint)))
                }
            case .enter, .space:
                if codePoint.isEmpty {
                    return (.cancelUnicodeInput, .transition(.none))
                } else {
                    return (.submitUnicodeInput(codePoint), .transition(.none))
                }
            case .escape:
                return (.cancelUnicodeInput, .transition(.none))
            case .英数, .かな, .tab, .forget, .function, .navigation, .editSegment, .suggest, .transformSelectedText, .deadKey, .startUnicodeInput, .unknown:
                return (.consume, .fallthrough)
            }
        }
    }
}
