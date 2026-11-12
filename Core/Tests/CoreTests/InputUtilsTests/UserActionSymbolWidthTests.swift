@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

private func makeEvent(
    logicalKey: String,
    characters: String,
    modifiers: KeyEventCore.ModifierFlag = []
) -> KeyEventCore {
    KeyEventCore(
        modifierFlags: modifiers,
        characters: characters,
        charactersIgnoringModifiers: logicalKey,
        keyCode: 0
    )
}

private func options(
    halfWidthSymbol: Bool = false,
    halfWidthSymbolAfterNumber: Bool = false,
    halfWidthSlash: Bool = false,
    inputStyle: Config.InputStyle.Value = .default
) -> UserAction.SymbolWidthOptions {
    .init(
        typeHalfWidthSymbol: halfWidthSymbol,
        typeHalfWidthSymbolAfterNumber: halfWidthSymbolAfterNumber,
        typeHalfWidthSlash: halfWidthSlash,
        inputStyle: inputStyle
    )
}

private func pieces(
    _ key: String,
    characters: String? = nil,
    modifiers: KeyEventCore.ModifierFlag = [],
    symbolWidth: UserAction.SymbolWidthOptions,
    precedingCharacter: Character? = nil
) -> [InputPiece]? {
    let action = UserAction.getUserAction(
        eventCore: makeEvent(logicalKey: key, characters: characters ?? key, modifiers: modifiers),
        inputLanguage: .japanese,
        typeBackSlash: false,
        symbolWidth: symbolWidth,
        precedingCharacter: precedingCharacter
    )
    guard case .input(let pieces) = action else {
        return nil
    }
    return pieces
}

private func typed(
    _ key: String,
    characters: String? = nil,
    modifiers: KeyEventCore.ModifierFlag = [],
    symbolWidth: UserAction.SymbolWidthOptions,
    precedingCharacter: Character? = nil
) -> String? {
    pieces(key, characters: characters, modifiers: modifiers, symbolWidth: symbolWidth, precedingCharacter: precedingCharacter)?
        .inputString(preferIntention: true)
}

// MARK: - 数字の後の記号

@Test func testSymbolAfterNumberIsHalfWidth() {
    let symbolWidth = options(halfWidthSymbolAfterNumber: true)
    #expect(typed(".", symbolWidth: symbolWidth, precedingCharacter: "1") == ".")
    #expect(typed(",", symbolWidth: symbolWidth, precedingCharacter: "0") == ",")
    #expect(typed(":", symbolWidth: symbolWidth, precedingCharacter: "2") == ":")
    #expect(typed("/", symbolWidth: symbolWidth, precedingCharacter: "1") == "/")
    #expect(typed("-", symbolWidth: symbolWidth, precedingCharacter: "3") == "-")
}

@Test func testSymbolNotAfterNumberKeepsJapaneseSymbol() {
    let symbolWidth = options(halfWidthSymbolAfterNumber: true)
    #expect(typed(":", symbolWidth: symbolWidth, precedingCharacter: "あ") == "：")
    #expect(typed("/", symbolWidth: symbolWidth, precedingCharacter: "あ") == "・")
    #expect(typed("-", symbolWidth: symbolWidth, precedingCharacter: "あ") == "ー")
    #expect(typed("-", symbolWidth: symbolWidth, precedingCharacter: nil) == "ー")
}

@Test func testOtherSymbolsAfterNumberAreUnchanged() {
    let symbolWidth = options(halfWidthSymbolAfterNumber: true)
    #expect(typed("!", symbolWidth: symbolWidth, precedingCharacter: "1") == "！")
    #expect(typed("[", symbolWidth: symbolWidth, precedingCharacter: "1") == "「")
}

@Test func testSymbolAfterNumberInAZIK() {
    let symbolWidth = options(halfWidthSymbolAfterNumber: true, inputStyle: .defaultAZIK)
    #expect(typed(":", symbolWidth: symbolWidth, precedingCharacter: "1") == ":")
    #expect(typed(":", symbolWidth: symbolWidth, precedingCharacter: "か") == "：")
}

@Test func testPunctuationNotAfterNumberKeepsPunctuationStyle() {
    let symbolWidth = options(halfWidthSymbolAfterNumber: true)
    // 句読点の種類の設定によって「。」か「．」になる
    #expect(typed(".", symbolWidth: symbolWidth, precedingCharacter: nil) != ".")
    #expect(typed(".", symbolWidth: symbolWidth, precedingCharacter: "あ") != ".")
    #expect(typed(",", symbolWidth: symbolWidth, precedingCharacter: "a") != ",")
    // 全角数字と漢数字の後は対象外
    #expect(typed(".", symbolWidth: symbolWidth, precedingCharacter: "１") != ".")
    #expect(typed(".", symbolWidth: symbolWidth, precedingCharacter: "一") != ".")
}

@Test func testSymbolAfterNumberRequiresSetting() {
    #expect(typed(".", symbolWidth: options(), precedingCharacter: "1") != ".")
}

@Test func testSymbolAfterNumberRespectsOptionInversion() {
    let symbolWidth = options(halfWidthSymbolAfterNumber: true)
    #expect(typed(".", characters: "≥", modifiers: [.option], symbolWidth: symbolWidth, precedingCharacter: "1") != ".")
}

@Test func testSymbolAfterNumberIsDisabledForKanaInput() {
    for inputStyle: Config.InputStyle.Value in [.defaultKanaJIS, .defaultKanaUS] {
        let symbolWidth = options(halfWidthSymbolAfterNumber: true, inputStyle: inputStyle)
        for symbol in [".", ",", ":", "/", "-"] {
            #expect(typed(symbol, symbolWidth: symbolWidth, precedingCharacter: "1") != symbol)
        }
    }
}

@Test func testSymbolAfterNumberKeepsRawInput() {
    let symbolWidth = options(halfWidthSymbolAfterNumber: true)
    #expect(pieces(".", symbolWidth: symbolWidth, precedingCharacter: "1") == [.key(intention: ".", input: ".", modifiers: [])])
}

// MARK: - 半角記号

@Test func testHalfWidthSymbol() {
    let symbolWidth = options(halfWidthSymbol: true)
    for symbol in ["!", "\"", "#", "$", "%", "&", "'", "(", ")", "=", "|", "`", "+", "*", "<", ">", "_", "^", "@", ";", ":", "¥"] {
        #expect(typed(symbol, symbolWidth: symbolWidth) == symbol)
    }
    #expect(typed("/", characters: "?", modifiers: [.shift], symbolWidth: symbolWidth) == "?")
    #expect(typed("\\", characters: "\\", modifiers: [.option], symbolWidth: symbolWidth) == "\\")
}

@Test func testHalfWidthSymbolKeepsJapanesePunctuation() {
    let symbolWidth = options(halfWidthSymbol: true)
    #expect(typed("-", symbolWidth: symbolWidth) == "ー")
    #expect(typed("[", symbolWidth: symbolWidth) == "「")
    #expect(typed("]", symbolWidth: symbolWidth) == "」")
    // 句読点は句読点の種類の設定に従う
    #expect(typed(".", symbolWidth: symbolWidth) != ".")
    #expect(typed(",", symbolWidth: symbolWidth) != ",")
}

@Test func testHalfWidthSymbolConvertsOtherJapaneseSymbols() {
    let symbolWidth = options(halfWidthSymbol: true)
    #expect(typed("{", symbolWidth: symbolWidth) == "{")
    #expect(typed("}", symbolWidth: symbolWidth) == "}")
    #expect(typed("/", symbolWidth: symbolWidth) == "/")
    #expect(typed("~", symbolWidth: symbolWidth) == "~")
}

@Test func testHalfWidthSymbolRequiresSetting() {
    #expect(typed("!", symbolWidth: options()) == "！")
    #expect(typed("(", symbolWidth: options()) == "（")
}

@Test func testHalfWidthSymbolKeepsAZIKKeys() {
    let symbolWidth = options(halfWidthSymbol: true, inputStyle: .defaultAZIK)
    #expect(typed(";", symbolWidth: symbolWidth) == "；")
    #expect(typed(":", symbolWidth: symbolWidth) == "：")
    #expect(typed("!", symbolWidth: symbolWidth) == "!")
}

@Test func testHalfWidthSymbolIsDisabledForKanaAndCustomInput() {
    for inputStyle: Config.InputStyle.Value in [.defaultKanaJIS, .defaultKanaUS, .custom] {
        let symbolWidth = options(halfWidthSymbol: true, inputStyle: inputStyle)
        #expect(typed("!", symbolWidth: symbolWidth) == "！")
        #expect(typed(";", symbolWidth: symbolWidth) == "；")
    }
}

// MARK: - 入力中の文字列との組み合わせ

private func makeSegmentsManager() -> SegmentsManager {
    SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
}

@MainActor
private func compose(_ text: String, symbolWidth: UserAction.SymbolWidthOptions, inputStyle: InputStyle) throws -> String {
    let manager = makeSegmentsManager()
    for key in text {
        let pieces = try #require(pieces(String(key), symbolWidth: symbolWidth, precedingCharacter: manager.characterBeforeCursor))
        manager.insertAtCursorPosition(pieces: pieces, inputStyle: inputStyle)
    }
    return manager.convertTarget
}

@MainActor
@Test func testComposingNumbersWithSymbols() throws {
    let symbolWidth = options(halfWidthSymbolAfterNumber: true)
    for text in ["3.14", "1,000", "12:30", "11/12", "03-1234"] {
        #expect(try compose(text, symbolWidth: symbolWidth, inputStyle: .roman2kana) == text)
    }
    #expect(try compose("ra-menn", symbolWidth: symbolWidth, inputStyle: .roman2kana) == "らーめん")
}

@MainActor
@Test func testComposingAZIKWithHalfWidthSymbol() throws {
    let symbolWidth = options(halfWidthSymbol: true, halfWidthSymbolAfterNumber: true, inputStyle: .defaultAZIK)
    #expect(try compose("ka;!", symbolWidth: symbolWidth, inputStyle: .mapped(id: .defaultAZIK)) == "かっ!")
    #expect(try compose("12:30", symbolWidth: symbolWidth, inputStyle: .mapped(id: .defaultAZIK)) == "12:30")
    #expect(try compose("ka:", symbolWidth: symbolWidth, inputStyle: .mapped(id: .defaultAZIK)) == "かー")
}

// MARK: - 「/」

@Test func testHalfWidthSlash() {
    let symbolWidth = options(halfWidthSlash: true)
    #expect(typed("/", symbolWidth: symbolWidth) == "/")
    #expect(typed("/", symbolWidth: symbolWidth, precedingCharacter: "あ") == "/")
    #expect(typed("/", symbolWidth: options(halfWidthSlash: true, inputStyle: .defaultAZIK)) == "/")
    // ほかの記号は変えない
    #expect(typed("!", symbolWidth: symbolWidth) == "！")
    #expect(typed("-", symbolWidth: symbolWidth) == "ー")
}

@Test func testHalfWidthSlashRequiresSetting() {
    #expect(typed("/", symbolWidth: options()) == "・")
}

@Test func testHalfWidthSlashIsDisabledForKanaInput() {
    for inputStyle: Config.InputStyle.Value in [.defaultKanaJIS, .defaultKanaUS] {
        #expect(typed("/", symbolWidth: options(halfWidthSlash: true, inputStyle: inputStyle)) == "・")
    }
}

@Test func testHalfWidthSlashKeepsOptionAndShiftVariants() {
    let symbolWidth = options(halfWidthSlash: true)
    #expect(typed("/", characters: "÷", modifiers: [.option], symbolWidth: symbolWidth) == "／")
    #expect(typed("/", characters: "?", modifiers: [.shift], symbolWidth: symbolWidth) == "？")
}

@MainActor
@Test func testComposingWithHalfWidthSymbol() throws {
    let symbolWidth = options(halfWidthSymbol: true)
    #expect(try compose("[ra-menn]!", symbolWidth: symbolWidth, inputStyle: .roman2kana) == "「らーめん」!")
    #expect(try compose("a/i~u{e}", symbolWidth: symbolWidth, inputStyle: .roman2kana) == "あ/い~う{え}")
}

@MainActor
@Test func testComposingWithHalfWidthSlash() throws {
    let symbolWidth = options(halfWidthSlash: true)
    #expect(try compose("a/i", symbolWidth: symbolWidth, inputStyle: .roman2kana) == "あ/い")
}

// MARK: - Control+L

@Test func testControlLConvertsToHalfWidthRomanWhenEnabled() {
    let event = makeEvent(logicalKey: "l", characters: "\u{0C}", modifiers: [.control])
    let enabled = UserAction.getUserAction(eventCore: event, inputLanguage: .japanese, halfWidthRomanWithControlL: true)
    let disabled = UserAction.getUserAction(eventCore: event, inputLanguage: .japanese, halfWidthRomanWithControlL: false)
    guard case .function(.ten) = enabled else {
        Issue.record("Expected Ctrl+L to be F10, got \(enabled)")
        return
    }
    guard case .function(.nine) = disabled else {
        Issue.record("Expected Ctrl+L to be F9, got \(disabled)")
        return
    }
}
