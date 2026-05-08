import Core
import Testing

private func makeControlEvent(
    logicalKey: String?,
    characters: String?,
    modifiers: KeyEventCore.ModifierFlag,
    keyCode: UInt16
) -> KeyEventCore {
    KeyEventCore(
        modifierFlags: modifiers,
        characters: characters,
        charactersIgnoringModifiers: logicalKey,
        keyCode: keyCode
    )
}

@Test func testUnhandledControlShortcutsAreNotConvertedToInput() {
    let controlBackquote = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: "`",
            characters: "`",
            modifiers: [.control],
            keyCode: 50
        ),
        inputLanguage: .japanese
    )
    guard case .unknown = controlBackquote else {
        Issue.record("Expected Ctrl+` to be unknown, got \(controlBackquote)")
        return
    }

    let controlShiftO = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: "o",
            characters: "O",
            modifiers: [.control, .shift],
            keyCode: 31
        ),
        inputLanguage: .japanese
    )
    guard case .unknown = controlShiftO else {
        Issue.record("Expected Ctrl+Shift+O to be unknown, got \(controlShiftO)")
        return
    }

    let numberKeyCodes: [(logicalKey: String, keyCode: UInt16)] = [
        ("1", 18),
        ("2", 19),
        ("3", 20),
        ("4", 21),
        ("5", 23),
        ("6", 22),
        ("7", 26),
        ("8", 28),
        ("9", 25),
        ("0", 29)
    ]
    for (logicalKey, keyCode) in numberKeyCodes {
        let controlNumber = UserAction.getUserAction(
            eventCore: makeControlEvent(
                logicalKey: logicalKey,
                characters: logicalKey,
                modifiers: [.control],
                keyCode: keyCode
            ),
            inputLanguage: .japanese
        )
        guard case .unknown = controlNumber else {
            Issue.record("Expected Ctrl+\(logicalKey) to be unknown, got \(controlNumber)")
            return
        }
    }

    let controlSpace = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: " ",
            characters: " ",
            modifiers: [.control],
            keyCode: 49
        ),
        inputLanguage: .japanese
    )
    guard case .unknown = controlSpace else {
        Issue.record("Expected Ctrl+Space to be unknown, got \(controlSpace)")
        return
    }

    let controlLeft = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: nil,
            characters: nil,
            modifiers: [.control],
            keyCode: 123
        ),
        inputLanguage: .japanese
    )
    guard case .unknown = controlLeft else {
        Issue.record("Expected Ctrl+Left to be unknown, got \(controlLeft)")
        return
    }
}

@Test func testKnownControlShortcutsKeepTheirActions() {
    let controlDelete = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: nil,
            characters: nil,
            modifiers: [.control],
            keyCode: 51
        ),
        inputLanguage: .japanese
    )
    guard case .forget = controlDelete else {
        Issue.record("Expected Ctrl+Delete to be forget, got \(controlDelete)")
        return
    }

    let controlH = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: "h",
            characters: "\u{08}",
            modifiers: [.control],
            keyCode: 4
        ),
        inputLanguage: .japanese
    )
    guard case .backspace = controlH else {
        Issue.record("Expected Ctrl+H to be backspace, got \(controlH)")
        return
    }

    let controlJ = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: "j",
            characters: "\n",
            modifiers: [.control],
            keyCode: 38
        ),
        inputLanguage: .japanese
    )
    guard case .function(.six) = controlJ else {
        Issue.record("Expected Ctrl+J to be function(.six), got \(controlJ)")
        return
    }

    let controlSemicolon = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: ";",
            characters: ";",
            modifiers: [.control],
            keyCode: 41
        ),
        inputLanguage: .japanese
    )
    guard case .function(.eight) = controlSemicolon else {
        Issue.record("Expected Ctrl+; to be function(.eight), got \(controlSemicolon)")
        return
    }

    let controlShiftU = UserAction.getUserAction(
        eventCore: makeControlEvent(
            logicalKey: "u",
            characters: "U",
            modifiers: [.control, .shift],
            keyCode: 32
        ),
        inputLanguage: .japanese
    )
    guard case .startUnicodeInput = controlShiftU else {
        Issue.record("Expected Ctrl+Shift+U to be startUnicodeInput, got \(controlShiftU)")
        return
    }
}

@Test func testUnknownActionsFallThroughToHostApplication() {
    let controlBackquoteEvent = makeControlEvent(
        logicalKey: "`",
        characters: "`",
        modifiers: [.control],
        keyCode: 50
    )

    let (noneAction, noneCallback) = InputState.none.event(
        eventCore: controlBackquoteEvent,
        userAction: .unknown,
        inputLanguage: .japanese,
        liveConversionEnabled: false,
        enableDebugWindow: false,
        enableSuggestion: false
    )
    guard case .fallthrough = noneAction, case .fallthrough = noneCallback else {
        Issue.record("Expected unknown action in none state to fall through, got \(noneAction), \(noneCallback)")
        return
    }

    let (composingAction, composingCallback) = InputState.composing.event(
        eventCore: controlBackquoteEvent,
        userAction: .unknown,
        inputLanguage: .japanese,
        liveConversionEnabled: false,
        enableDebugWindow: false,
        enableSuggestion: false
    )
    guard case .fallthrough = composingAction, case .fallthrough = composingCallback else {
        Issue.record("Expected unknown action in composing state to fall through, got \(composingAction), \(composingCallback)")
        return
    }
}
