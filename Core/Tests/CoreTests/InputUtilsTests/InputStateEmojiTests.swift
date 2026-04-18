import Core
import KanaKanjiConverterModule
import Testing

/// 絵文字入力モード (`.emojiInput`, `.emojiInputNested`) の遷移テスト
private let zeroEvent = KeyEventCore(
    modifierFlags: [],
    characters: nil,
    charactersIgnoringModifiers: nil,
    keyCode: 0
)

/// 日本語モードで全角コロン `：` を打ったのと同等の UserAction を作る
private func colonInputAction() -> UserAction {
    .input([.key(intention: "：", input: ":", modifiers: [])])
}

/// 任意の半角文字を日本語モードで打ったのと同等の UserAction を作る
private func asciiInputAction(_ c: Character) -> UserAction {
    guard let fullwidth = Core.KeyMap.h2zMap(c) else {
        return .input([.character(c)])
    }
    return .input([.key(intention: fullwidth, input: c, modifiers: [])])
}

private func runEvent(
    state: InputState,
    userAction: UserAction,
    inputLanguage: InputLanguage = .japanese,
    emojiInputEnabled: Bool = true,
    emojiInputTrigger: String = "："
) -> (ClientAction, ClientActionCallback) {
    state.event(
        eventCore: zeroEvent,
        userAction: userAction,
        inputLanguage: inputLanguage,
        liveConversionEnabled: false,
        enableDebugWindow: false,
        enableSuggestion: false,
        emojiInputEnabled: emojiInputEnabled,
        emojiInputTrigger: emojiInputTrigger
    )
}

// MARK: - トリガー発動

@Test func testColonFromNoneEntersEmojiInput() async throws {
    let (action, callback) = runEvent(state: .none, userAction: colonInputAction())
    guard case .enterEmojiInputMode = action else {
        Issue.record("expected .enterEmojiInputMode, got \(action)")
        return
    }
    guard case .transition(.emojiInput("")) = callback else {
        Issue.record("expected .transition(.emojiInput(empty)), got \(callback)")
        return
    }
}

@Test func testColonFromComposingEntersEmojiInputNested() async throws {
    let (action, callback) = runEvent(state: .composing, userAction: colonInputAction())
    guard case .enterEmojiInputMode = action else {
        Issue.record("expected .enterEmojiInputMode, got \(action)")
        return
    }
    guard case .transition(.emojiInputNested("")) = callback else {
        Issue.record("expected .transition(.emojiInputNested(empty)), got \(callback)")
        return
    }
}

@Test func testColonFromPreviewingEntersEmojiInputNested() async throws {
    let (_, callback) = runEvent(state: .previewing, userAction: colonInputAction())
    guard case .transition(.emojiInputNested("")) = callback else {
        Issue.record("expected .transition(.emojiInputNested(empty)), got \(callback)")
        return
    }
}

@Test func testColonFromSelectingEntersEmojiInputNested() async throws {
    let (_, callback) = runEvent(state: .selecting, userAction: colonInputAction())
    guard case .transition(.emojiInputNested("")) = callback else {
        Issue.record("expected .transition(.emojiInputNested(empty)), got \(callback)")
        return
    }
}

// MARK: - 無効化時は発動しない

@Test func testColonDoesNotTriggerWhenDisabled() async throws {
    let (action, _) = runEvent(state: .none, userAction: colonInputAction(), emojiInputEnabled: false)
    // enterEmojiInputMode が返ってこないことを確認
    if case .enterEmojiInputMode = action {
        Issue.record("emoji input should not trigger when disabled")
    }
}

@Test func testEnglishModeColonDoesNotTriggerEmoji() async throws {
    // 英語モードでは :key(intention: nil) になり preferIntention:true でも "：" 一致しない
    let englishColon: UserAction = .input([.character(":")])
    let (action, _) = runEvent(state: .none, userAction: englishColon, inputLanguage: .english)
    if case .enterEmojiInputMode = action {
        Issue.record("emoji input should not trigger in English mode")
    }
}

// MARK: - emojiInput 中のキー操作

@Test func testLetterAppendsToEmojiQuery() async throws {
    let (action, callback) = runEvent(state: .emojiInput("sm"), userAction: asciiInputAction("i"))
    guard case .appendToEmojiInput(let appended) = action else {
        Issue.record("expected .appendToEmojiInput, got \(action)")
        return
    }
    #expect(appended == "i")
    guard case .transition(.emojiInput("smi")) = callback else {
        Issue.record("expected .transition(.emojiInput(smi)), got \(callback)")
        return
    }
}

@Test func testBackspaceShrinksEmojiQuery() async throws {
    let (action, callback) = runEvent(state: .emojiInput("smile"), userAction: .backspace)
    if case .removeLastEmojiInput = action {} else {
        Issue.record("expected .removeLastEmojiInput, got \(action)")
    }
    guard case .transition(.emojiInput("smil")) = callback else {
        Issue.record("expected .transition(.emojiInput(smil)), got \(callback)")
        return
    }
}

@Test func testBackspaceOnEmptyQueryCancels() async throws {
    let (action, callback) = runEvent(state: .emojiInput(""), userAction: .backspace)
    if case .cancelEmojiInput = action {} else {
        Issue.record("expected .cancelEmojiInput, got \(action)")
    }
    guard case .transition(.none) = callback else {
        Issue.record("expected .transition(.none), got \(callback)")
        return
    }
}

@Test func testBackspaceOnEmptyNestedQueryReturnsToComposing() async throws {
    let (_, callback) = runEvent(state: .emojiInputNested(""), userAction: .backspace)
    guard case .transition(.composing) = callback else {
        Issue.record("expected .transition(.composing), got \(callback)")
        return
    }
}

@Test func testEnterSubmitsEmojiCandidate() async throws {
    let (action, callback) = runEvent(state: .emojiInput("smile"), userAction: .enter)
    if case .submitSelectedEmojiCandidate = action {} else {
        Issue.record("expected .submitSelectedEmojiCandidate, got \(action)")
    }
    guard case .transition(.none) = callback else {
        Issue.record("expected .transition(.none), got \(callback)")
        return
    }
}

@Test func testNestedEnterReturnsToComposing() async throws {
    let (_, callback) = runEvent(state: .emojiInputNested("smile"), userAction: .enter)
    guard case .transition(.composing) = callback else {
        Issue.record("expected .transition(.composing), got \(callback)")
        return
    }
}

@Test func testEscapeCancels() async throws {
    let (action, callback) = runEvent(state: .emojiInput("smile"), userAction: .escape)
    if case .cancelEmojiInput = action {} else {
        Issue.record("expected .cancelEmojiInput, got \(action)")
    }
    guard case .transition(.none) = callback else {
        Issue.record("expected .transition(.none), got \(callback)")
        return
    }
}

@Test func testNavigationDownSelectsNext() async throws {
    let (action, _) = runEvent(state: .emojiInput("smile"), userAction: .navigation(.down))
    if case .selectNextEmojiCandidate = action {} else {
        Issue.record("expected .selectNextEmojiCandidate, got \(action)")
    }
}

@Test func testNavigationUpSelectsPrev() async throws {
    let (action, _) = runEvent(state: .emojiInput("smile"), userAction: .navigation(.up))
    if case .selectPrevEmojiCandidate = action {} else {
        Issue.record("expected .selectPrevEmojiCandidate, got \(action)")
    }
}

@Test func testSecondTriggerCharSubmitsSelected() async throws {
    // "smile" のクエリ中にもう一度「：」を打つと選択中候補を確定
    let (action, callback) = runEvent(state: .emojiInput("smile"), userAction: colonInputAction())
    if case .submitSelectedEmojiCandidate = action {} else {
        Issue.record("expected .submitSelectedEmojiCandidate, got \(action)")
    }
    guard case .transition(.none) = callback else {
        Issue.record("expected .transition(.none), got \(callback)")
        return
    }
}

// MARK: - カスタムトリガー文字

@Test func testCustomTriggerFiresOnly() async throws {
    // トリガーを "；" (全角セミコロン) に変更したら、コロンでは発動しない
    let customTrigger = "；"
    let (action, _) = runEvent(
        state: .none,
        userAction: colonInputAction(),
        emojiInputTrigger: customTrigger
    )
    if case .enterEmojiInputMode = action {
        Issue.record("colon should not trigger when custom trigger is set to semicolon")
    }
}
