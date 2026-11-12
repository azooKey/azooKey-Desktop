import Core
import Testing

private func resolve(
    _ characters: String?,
    modifierFlags: KeyEventCore.ModifierFlag = [],
    inputLanguage: InputLanguage = .japanese,
    inputState: InputState = .none,
    inputStyle: Config.InputStyle.Value = .default
) -> String? {
    SlashDirectInputResolver.resolve(
        characters: characters,
        modifierFlags: modifierFlags,
        inputLanguage: inputLanguage,
        inputState: inputState,
        inputStyle: inputStyle
    )
}

@Test func testSlashIsInsertedDirectlyWhenNotComposing() {
    #expect(resolve("/") == "/")
    #expect(resolve("/", inputStyle: .defaultAZIK) == "/")
    #expect(resolve("/", inputStyle: .custom) == "/")
}

@Test func testSlashDuringCompositionIsNotInsertedDirectly() {
    for state: InputState in [.composing, .previewing, .selecting, .replaceSuggestion] {
        #expect(resolve("/", inputState: state) == nil)
    }
}

@Test func testSlashDirectInputIgnoresOtherKeys() {
    #expect(resolve("a") == nil)
    #expect(resolve("!") == nil)
    #expect(resolve(nil) == nil)
    #expect(resolve("?", modifierFlags: [.shift]) == nil)
    #expect(resolve("/", modifierFlags: [.option]) == nil)
}

@Test func testSlashDirectInputIsDisabledForEnglishAndKanaInput() {
    #expect(resolve("/", inputLanguage: .english) == nil)
    #expect(resolve("/", inputStyle: .defaultKanaJIS) == nil)
    #expect(resolve("/", inputStyle: .defaultKanaUS) == nil)
}
