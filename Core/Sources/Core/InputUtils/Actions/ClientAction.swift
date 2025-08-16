import InputMethodKit
import KanaKanjiConverterModule

public enum ClientAction {
    case `consume`
    case `fallthrough`
    case showCandidateWindow
    case hideCandidateWindow
    case appendToMarkedText(String)
    case appendPieceToMarkedText(InputPiece)

    /// Marked Textを経由せずにインサートするコマンド。InputStateがnoneの場合のみ有効
    case insertWithoutMarkedText(String)
    case removeLastMarkedText

    case commitMarkedText
    /// Shift+←→で選択範囲をエディットするコマンド
    case editSegment(Int)

    /// previwingに入るコマンド
    case enterFirstCandidatePreviewMode

    /// スペースを押して`.selecting`に入るコマンド
    case enterCandidateSelectionMode
    case submitSelectedCandidate
    case selectNextCandidate
    case selectPrevCandidate
    case selectNumberCandidate(Int)

    case selectInputLanguage(InputLanguage)
    case commitMarkedTextAndSelectInputLanguage(InputLanguage)

    /// MarkedTextを確定して、さらに追加で入力する
    case commitMarkedTextAndAppendToMarkedText(String)

    /// 現在選ばれている候補を確定して、さらに追加で入力する
    ///  - note:`commitMarkedTextAndAppendToMarkedText`はMarkedText全体を一度に確定するが、`submitSelectedCandidateAndAppendToMarkedText`の場合は部分的に確定されることがあるという違いがある
    case submitSelectedCandidateAndAppendToMarkedText(String)
    case submitSelectedCandidateAndAppendPieceToMarkedText(InputPiece)
    case submitSelectedCandidateAndEnterFirstCandidatePreviewMode

    /// デバッグウィンドウを表示するコマンド
    case enableDebugWindow
    case disableDebugWindow

    /// 学習のリセット
    case forgetMemory

    // Fnキーでの変換
    case submitKatakanaCandidate
    case submitHiraganaCandidate
    case submitHankakuKatakanaCandidate
    case submitFullWidthRomanCandidate
    case submitHalfWidthRomanCandidate

    // PredictiveSuggestion
    case requestPredictiveSuggestion

    // ReplaceSuggestion
    case requestReplaceSuggestion
    case selectNextReplaceSuggestionCandidate
    case selectPrevReplaceSuggestionCandidate
    case submitReplaceSuggestionCandidate
    case hideReplaceSuggestionWindow

    // Selected Text Transform
    case showPromptInputWindow
    case transformSelectedText(String, String)  // (selectedText, prompt)

    // DeadKey handling
    case transitionToDeadKeyComposition(String)
    case insertDiacriticAndTransition(String, InputState)
    case commitMarkedTextAndReplaceWith(String)
    case commitMarkedTextAndThenInsert(String)
    case stopCompositionAndSelectInputLanguage(InputLanguage)

    case stopComposition
}

public enum ClientActionCallback {
    case `fallthrough`
    case transition(InputState)
    ///
    case basedOnBackspace(ifIsEmpty: InputState, ifIsNotEmpty: InputState)
    case basedOnSubmitCandidate(ifIsEmpty: InputState, ifIsNotEmpty: InputState)
}
