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
