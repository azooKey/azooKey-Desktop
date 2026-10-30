@testable import Core
import Foundation
import Testing

@Test func importGoogleJapaneseInputTSVWithComments() {
    let text = [
        "!Dictionary File",
        "!Version: 1.0",
        "!User Dictionary Name: 化学統合版",
        ["くろむこう", "Cr鋼", "名詞", "Crを特徴とする鋼材。"].joined(separator: "\t"),
        ["えんそいおん", "Clイオン", "名詞", "Clの電荷を持つイオン。"].joined(separator: "\t"),
        ["こめなし", "コメントなし", "名詞"].joined(separator: "\t")
    ].joined(separator: "\n")

    let result = UserDictionaryTextCodec.importEntries(from: text, format: .automatic)

    #expect(result.dictionaryName == "化学統合版")
    #expect(result.entries.count == 3)
    #expect(result.entries[0].reading == "くろむこう")
    #expect(result.entries[0].word == "Cr鋼")
    #expect(result.entries[0].hint == "Crを特徴とする鋼材。")
    #expect(result.entries[2].hint == nil)
}

@Test func exportGoogleJapaneseInputTSV() {
    let entries = [
        Config.UserDictionaryEntry(word: "Cohen-Macaulay", reading: "こーえんまこーれー", hint: "深さが Krull 次元に等しいことを表す性質"),
        Config.UserDictionaryEntry(word: "正則列", reading: "せいそくれつ", hint: nil)
    ]

    let exported = UserDictionaryTextCodec.exportEntries(entries, dictionaryName: "ユーザ辞書")

    #expect(exported.contains("!User Dictionary Name: ユーザ辞書"))
    #expect(exported.contains(["こーえんまこーれー", "Cohen-Macaulay", "名詞", "深さが Krull 次元に等しいことを表す性質"].joined(separator: "\t")))
    #expect(exported.contains(["せいそくれつ", "正則列", "名詞", ""].joined(separator: "\t")))
}

@Test func decodeUTF16DictionaryWithoutLeavingBOM() throws {
    let text = ["よみ", "単語", "名詞", "コメント"].joined(separator: "\t")
    let littleEndianData = Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!
    let bigEndianData = Data([0xFE, 0xFF]) + text.data(using: .utf16BigEndian)!

    let littleEndianResult = UserDictionaryTextCodec.importEntries(
        from: try #require(UserDictionaryTextCodec.decodeText(from: littleEndianData)),
        format: .googleJapaneseInput
    )
    let bigEndianResult = UserDictionaryTextCodec.importEntries(
        from: try #require(UserDictionaryTextCodec.decodeText(from: bigEndianData)),
        format: .googleJapaneseInput
    )

    #expect(littleEndianResult.entries.first?.reading == "よみ")
    #expect(bigEndianResult.entries.first?.reading == "よみ")
}
