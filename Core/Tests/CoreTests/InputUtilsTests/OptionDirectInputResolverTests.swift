import Core
import Testing

@Test func testOptionDirectInputResolverReturnsFullWidthTextForJapaneseNoneState() async throws {
    let option: KeyEventCore.ModifierFlag = [.option]
    let shiftOption: KeyEventCore.ModifierFlag = [.option, .shift]

    #expect(OptionDirectInputResolver.resolve(
        characters: "a",
        modifierFlags: option,
        inputLanguage: .japanese,
        inputState: .none,
        typeBackSlash: false
    ) == "ａ")
    #expect(OptionDirectInputResolver.resolve(
        characters: "A",
        modifierFlags: shiftOption,
        inputLanguage: .japanese,
        inputState: .none,
        typeBackSlash: false
    ) == "Ａ")
    #expect(OptionDirectInputResolver.resolve(
        characters: "-",
        modifierFlags: option,
        inputLanguage: .japanese,
        inputState: .none,
        typeBackSlash: false
    ) == "－")
    #expect(OptionDirectInputResolver.resolve(
        characters: "/",
        modifierFlags: shiftOption,
        inputLanguage: .japanese,
        inputState: .none,
        typeBackSlash: false
    ) == "／")
    #expect(OptionDirectInputResolver.resolve(
        characters: "¥",
        modifierFlags: option,
        inputLanguage: .japanese,
        inputState: .none,
        typeBackSlash: false
    ) == "￥")
    #expect(OptionDirectInputResolver.resolve(
        characters: "¥",
        modifierFlags: option,
        inputLanguage: .japanese,
        inputState: .none,
        typeBackSlash: true
    ) == "＼")
}

@Test func testOptionDirectInputResolverRejectsUnsupportedContext() async throws {
    let option: KeyEventCore.ModifierFlag = [.option]

    #expect(OptionDirectInputResolver.resolve(
        characters: "a",
        modifierFlags: [],
        inputLanguage: .japanese,
        inputState: .none,
        typeBackSlash: false
    ) == nil)
    #expect(OptionDirectInputResolver.resolve(
        characters: "a",
        modifierFlags: option,
        inputLanguage: .english,
        inputState: .none,
        typeBackSlash: false
    ) == nil)
    #expect(OptionDirectInputResolver.resolve(
        characters: "a",
        modifierFlags: option,
        inputLanguage: .japanese,
        inputState: .composing,
        typeBackSlash: false
    ) == nil)
    #expect(OptionDirectInputResolver.resolve(
        characters: "\r",
        modifierFlags: option,
        inputLanguage: .japanese,
        inputState: .none,
        typeBackSlash: false
    ) == nil)
}
