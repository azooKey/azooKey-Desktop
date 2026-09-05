import Core
import Testing

private func disposition(
    event: KeyEventCore,
    state: ConverterInputState = .none,
    language: InputLanguage = .japanese,
    hasPendingKeyEvents: Bool = false
) -> ConverterClientEventDisposition {
    ConverterClientEventRouter.disposition(
        event: event,
        context: .init(
            acknowledgedInputState: state,
            acknowledgedInputLanguage: language,
            hasPendingKeyEvents: hasPendingKeyEvents
        )
    )
}

@Test func printableJapaneseInputIsSentToServer() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [],
                characters: "a",
                charactersIgnoringModifiers: "a",
                keyCode: 0
            )
        ) == .sendToServer
    )
}

@Test func backspaceFallsThroughWhenAcknowledgedStateIsEmpty() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [],
                characters: nil,
                charactersIgnoringModifiers: nil,
                keyCode: 51
            )
        ) == .fallthroughToApplication
    )
}

@Test func backspaceIsConsumedWhileEarlierKeyEventIsPending() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [],
                characters: nil,
                charactersIgnoringModifiers: nil,
                keyCode: 51
            ),
            hasPendingKeyEvents: true
        ) == .sendToServer
    )
}

@Test func commandShortcutAlwaysFallsThroughWhileServerIsDelayed() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [.command],
                characters: "c",
                charactersIgnoringModifiers: "c",
                keyCode: 8
            ),
            state: .composing,
            hasPendingKeyEvents: true
        ) == .fallthroughToApplication
    )
}

@Test func unknownControlShortcutIsConsumedOnlyDuringComposition() {
    let event = KeyEventCore(
        modifierFlags: [.control],
        characters: "q",
        charactersIgnoringModifiers: "q",
        keyCode: 12
    )

    #expect(disposition(event: event) == .fallthroughToApplication)
    #expect(disposition(event: event, state: .composing) == .sendToServer)
}

private func provisionalMarkedText(
    event: KeyEventCore,
    state: ConverterInputState = .none,
    language: InputLanguage = .japanese,
    hasPendingKeyEvents: Bool = false
) -> String? {
    ConverterClientEventRouter.provisionalMarkedText(
        event: event,
        context: .init(
            acknowledgedInputState: state,
            acknowledgedInputLanguage: language,
            hasPendingKeyEvents: hasPendingKeyEvents
        )
    )
}

private let letterB = KeyEventCore(
    modifierFlags: [],
    characters: "b",
    charactersIgnoringModifiers: "b",
    keyCode: 11
)

@Test func firstCharacterIsPlacedAsProvisionalMarkedText() {
    #expect(provisionalMarkedText(event: letterB) == "b")
    #expect(provisionalMarkedText(event: letterB, language: .english) == "b")
}

@Test func provisionalMarkedTextKeepsRawKeyForKanaInput() {
    // かな入力の変換は Server の入力テーブルが行うため、Client は生のキーを置く
    let event = KeyEventCore(
        modifierFlags: [],
        characters: "r",
        charactersIgnoringModifiers: "r",
        keyCode: 15
    )
    #expect(provisionalMarkedText(event: event) == "r")
}

@Test func provisionalMarkedTextIsAccumulatedWhileEarlierKeyEventIsPending() {
    // acknowledged state が古くても文字は返す。積み上げは Client が行う
    #expect(provisionalMarkedText(event: letterB, hasPendingKeyEvents: true) == "b")
}

@Test func provisionalMarkedTextIsNotPlacedDuringComposition() {
    #expect(provisionalMarkedText(event: letterB, state: .composing) == nil)
}

@Test func provisionalMarkedTextIsNotPlacedForNonInputKeys() {
    let backspace = KeyEventCore(
        modifierFlags: [],
        characters: nil,
        charactersIgnoringModifiers: nil,
        keyCode: 51
    )
    let commandShortcut = KeyEventCore(
        modifierFlags: [.command],
        characters: "c",
        charactersIgnoringModifiers: "c",
        keyCode: 8
    )
    #expect(provisionalMarkedText(event: backspace) == nil)
    #expect(provisionalMarkedText(event: commandShortcut) == nil)
}
