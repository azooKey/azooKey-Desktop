import Core
import Testing

private func disposition(
    event: KeyEventCore,
    state: ConverterInputState = .none,
    language: InputLanguage = .japanese
) -> ConverterClientEventDisposition {
    ConverterClientEventRouter.disposition(
        event: event,
        context: .init(
            acknowledgedInputState: state,
            acknowledgedInputLanguage: language
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

@Test func backspaceIsConsumedWhileComposing() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [],
                characters: nil,
                charactersIgnoringModifiers: nil,
                keyCode: 51
            ),
            state: .composing
        ) == .sendToServer
    )
}

@Test func commandShortcutAlwaysFallsThroughWhileComposing() {
    #expect(
        disposition(
            event: KeyEventCore(
                modifierFlags: [.command],
                characters: "c",
                charactersIgnoringModifiers: "c",
                keyCode: 8
            ),
            state: .composing
        ) == .fallthroughToApplication
    )
}

@Test func directEnglishInputDoesNotNeedServer() {
    for event in [
        KeyEventCore(modifierFlags: [], characters: "a", charactersIgnoringModifiers: "a", keyCode: 0),
        KeyEventCore(modifierFlags: [], characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36),
        KeyEventCore(modifierFlags: [], characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", keyCode: 51),
        KeyEventCore(modifierFlags: [], characters: "\t", charactersIgnoringModifiers: "\t", keyCode: 48),
        KeyEventCore(modifierFlags: [], characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
    ] {
        #expect(disposition(event: event, language: .english) == .fallthroughToApplication)
        #expect(disposition(event: event, state: .composing, language: .english) == .sendToServer)
    }
}

@Test func directEnglishInputPreservesBackslashSetting() {
    let event = KeyEventCore(modifierFlags: [], characters: "¥", charactersIgnoringModifiers: "¥", keyCode: 93)
    #expect(ConverterClientEventRouter.disposition(
        event: event,
        context: .init(acknowledgedInputLanguage: .english, typeBackSlash: true)
    ) == .insertText("\\"))
}

@Test func englishDeadKeyStillUsesServerState() {
    let event = KeyEventCore(modifierFlags: [], characters: "a", charactersIgnoringModifiers: "a", keyCode: 0)
    #expect(disposition(event: event, state: .attachDiacritic("´"), language: .english) == .sendToServer)
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
