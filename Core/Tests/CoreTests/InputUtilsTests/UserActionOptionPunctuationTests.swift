import Core
import Foundation
import KanaKanjiConverterModule
import Testing

private func inputPiecesToString(_ inputPieces: [InputPiece]) -> String {
    String(inputPieces.compactMap {
        switch $0 {
        case .character(let c): c
        case .key(intention: let cint, input: let cinp, modifiers: _): cint ?? cinp
        case .compositionSeparator: nil
        }
    })
}

private func inputString(from action: UserAction) -> String? {
    guard case .input(let pieces) = action else {
        return nil
    }
    return inputPiecesToString(pieces)
}

private func makeEvent(
    logicalKey: String,
    characters: String?,
    modifiers: KeyEventCore.ModifierFlag
) -> KeyEventCore {
    KeyEventCore(
        modifierFlags: modifiers,
        characters: characters,
        charactersIgnoringModifiers: logicalKey,
        keyCode: 0
    )
}

@Test func testOptionPunctuationMappings() async throws {
    let defaults = UserDefaults.standard
    let key = Config.PunctuationStyle.key
    let originalData = defaults.data(forKey: key)
    defer {
        if let data = originalData {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    let option: KeyEventCore.ModifierFlag = [.option]
    let shiftOption: KeyEventCore.ModifierFlag = [.shift, .option]

    Config.PunctuationStyle().value = .kutenAndToten
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: ",", characters: "≤", modifiers: option),
        inputLanguage: .japanese
    )) == "，")
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: ".", characters: "≥", modifiers: option),
        inputLanguage: .japanese
    )) == "．")

    Config.PunctuationStyle().value = .periodAndComma
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: ",", characters: "≤", modifiers: option),
        inputLanguage: .japanese
    )) == "、")
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: ".", characters: "≥", modifiers: option),
        inputLanguage: .japanese
    )) == "。")

    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: "[", characters: "[", modifiers: option),
        inputLanguage: .japanese
    )) == "［")
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: "[", characters: "{", modifiers: shiftOption),
        inputLanguage: .japanese
    )) == "｛")
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: "]", characters: "]", modifiers: option),
        inputLanguage: .japanese
    )) == "］")
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: "]", characters: "}", modifiers: shiftOption),
        inputLanguage: .japanese
    )) == "｝")
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: ",", characters: "¯", modifiers: shiftOption),
        inputLanguage: .japanese
    )) == "¯")
    #expect(inputString(from: UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: ".", characters: "˘", modifiers: shiftOption),
        inputLanguage: .japanese
    )) == "˘")
}
