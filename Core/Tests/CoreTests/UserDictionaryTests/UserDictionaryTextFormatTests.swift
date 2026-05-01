@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@Test func importGoogleJapaneseInputTSVWithComments() {
    let text = """
    !Dictionary File
    !Version: 1.0
    !User Dictionary Name: 化学統合版
    くろむこう\tCr鋼\t名詞\tCrを特徴とする鋼材。
    えんそいおん\tClイオン\t名詞\tClイの電荷を持つイオン。
    こめなし\tコメントなし\t名詞
    """

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

    let exported = UserDictionaryTextCodec.exportEntries(entries, dictionaryName: "可換環論")

    #expect(exported.contains("!User Dictionary Name: 可換環論"))
    #expect(exported.contains("こーえんまこーれー\tCohen-Macaulay\t名詞\t深さが Krull 次元に等しいことを表す性質"))
    #expect(exported.contains("せいそくれつ\t正則列\t名詞\t"))
}

@Test func decodeLegacySingleDictionaryValue() throws {
    let legacy = """
    {
      "items": [
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "word": "azooKey",
          "reading": "あずーきー",
          "hint": "アプリ"
        }
      ]
    }
    """

    let value = try JSONDecoder().decode(Config.UserDictionary.Value.self, from: Data(legacy.utf8))

    #expect(value.dictionaries.count == 1)
    #expect(value.dictionaries[0].name == "ユーザ辞書")
    #expect(value.dictionaries[0].isEnabled)
    #expect(value.enabledItems.count == 1)
}

@Test func dynamicUserDictionaryFilteringKeepsConvertibleEntries() {
    #expect(SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "コーエンマコーレー", for: "コーエン"))
    #expect(SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "コーエンマコーレー", for: "コーエンマコーレー"))
    #expect(SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "コーエンマコーレー", for: "アカイコーエン"))
    #expect(SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "コーエンマコーレー", for: "アカイコーエンマコーレーデス"))
    #expect(SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "カン", for: "アカン"))
}

@Test func dynamicUserDictionaryFilteringDropsUnrelatedEntries() {
    #expect(!SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "セイソクレツ", for: "コーエン"))
    #expect(!SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "", for: "コーエン"))
    #expect(!SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "コーエン", for: ""))
}

@Test func rebuildUserDictionaryIndexWritesSearchFiles() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("azookey-user-dictionary-index-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    try UserDictionaryIndexStore(directoryURL: directory).rebuild(entries: [
        .init(word: "Cohen-Macaulay", ruby: "コーエンマコーレー", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5),
        .init(word: "正則列", ruby: "セイソクレツ", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    ])

    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("user.louds").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("user.loudschars2").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("user0.loudstxt3").path))
}
