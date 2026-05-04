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

@Test func decodeUTF16DictionaryWithoutLeavingBOM() throws {
    let text = "よみ\t単語\t名詞\tコメント"
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

    _ = try UserDictionaryIndexStore(directoryURL: directory).rebuild(
        entries: [
            .init(word: "Cohen-Macaulay", ruby: "コーエンマコーレー", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5),
            .init(word: "正則列", ruby: "セイソクレツ", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
        ],
        userRevision: 12,
        systemRevision: 34
    )

    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("user.louds").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("user.loudschars2").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("user0.loudstxt3").path))
    #expect(UserDictionaryIndexStore(directoryURL: directory).metadata() == .init(
        userRevision: 12,
        systemRevision: 34,
        indexedEntryCount: 2,
        skippedEntryCount: 0
    ))
}

@Test func userDictionaryIndexReportsSkippedUnsupportedReadings() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("azookey-user-dictionary-index-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let result = try UserDictionaryIndexStore(directoryURL: directory).rebuild(
        entries: [
            .init(word: "unsupported", ruby: "\u{10FFFF}", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
        ],
        userRevision: 56,
        systemRevision: 78
    )

    #expect(result.indexedEntryCount == 0)
    #expect(result.skippedEntryCount == 1)
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("user.louds").path))
    #expect(UserDictionaryIndexStore(directoryURL: directory).metadata() == .init(
        userRevision: 56,
        systemRevision: 78,
        indexedEntryCount: 0,
        skippedEntryCount: 1
    ))
}

@Test func userDictionaryIndexRequiresFilesWhenMetadataReportsIndexedEntries() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("azookey-user-dictionary-index-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let store = UserDictionaryIndexStore(directoryURL: directory)
    let metadata = UserDictionaryIndexStore.Metadata(
        userRevision: 90,
        systemRevision: 12,
        indexedEntryCount: 1,
        skippedEntryCount: 0
    )

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(metadata)
    try data.write(to: directory.appendingPathComponent("metadata.json", isDirectory: false))

    #expect(!store.hasUsableIndex(for: metadata))

    for fileName in ["user.louds", "user.loudschars2", "user0.loudstxt3"] {
        try Data().write(to: directory.appendingPathComponent(fileName, isDirectory: false))
    }

    #expect(store.hasUsableIndex(for: metadata))
}

@Test func userDictionaryIndexStatusReportsReadyAndStaleCaches() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("azookey-user-dictionary-index-\(UUID().uuidString)", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    #expect(UserDictionaryIndexController.status(
        directoryURL: directory,
        currentUserRevision: 1,
        currentSystemRevision: 2,
        entryCount: 3
    ) == .notBuilt(entryCount: 3))

    _ = try UserDictionaryIndexStore(directoryURL: directory).rebuild(
        entries: [
            .init(word: "Cohen-Macaulay", ruby: "コーエンマコーレー", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
        ],
        userRevision: 1,
        systemRevision: 2
    )

    switch UserDictionaryIndexController.status(
        directoryURL: directory,
        currentUserRevision: 1,
        currentSystemRevision: 2,
        entryCount: 1
    ) {
    case .ready(let summary):
        #expect(summary.indexedEntryCount == 1)
        #expect(summary.skippedEntryCount == 0)
    default:
        Issue.record("Expected a ready user dictionary index")
    }

    switch UserDictionaryIndexController.status(
        directoryURL: directory,
        currentUserRevision: 2,
        currentSystemRevision: 2,
        entryCount: 4
    ) {
    case .needsRebuild(let currentEntryCount, let existing):
        #expect(currentEntryCount == 4)
        #expect(existing?.indexedEntryCount == 1)
    default:
        Issue.record("Expected a stale user dictionary index")
    }
}

@Test func userDictionaryRevisionIgnoresDictionaryNameOnlyChanges() {
    let defaults = UserDefaults.standard
    let key = Config.UserDictionary.key
    let revisionKey = Config.UserDictionary.revisionKey
    let oldData = defaults.data(forKey: key)
    let oldRevision = defaults.object(forKey: revisionKey)
    defer {
        if let oldData {
            defaults.set(oldData, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        if let oldRevision {
            defaults.set(oldRevision, forKey: revisionKey)
        } else {
            defaults.removeObject(forKey: revisionKey)
        }
    }

    defaults.removeObject(forKey: key)
    defaults.removeObject(forKey: revisionKey)

    var value = Config.UserDictionary.default
    value.dictionaries[0].name = "表示名だけ変更"
    Config.UserDictionary().value = value
    #expect(defaults.integer(forKey: revisionKey) == 0)

    value.dictionaries[0].items[0].hint = "コメント変更"
    Config.UserDictionary().value = value
    #expect(defaults.integer(forKey: revisionKey) == 1)
}

@Test func systemUserDictionaryRevisionIgnoresLastUpdateOnlyChanges() {
    let defaults = UserDefaults.standard
    let key = Config.SystemUserDictionary.key
    let revisionKey = Config.SystemUserDictionary.revisionKey
    let oldData = defaults.data(forKey: key)
    let oldRevision = defaults.object(forKey: revisionKey)
    defer {
        if let oldData {
            defaults.set(oldData, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        if let oldRevision {
            defaults.set(oldRevision, forKey: revisionKey)
        } else {
            defaults.removeObject(forKey: revisionKey)
        }
    }

    defaults.removeObject(forKey: key)
    defaults.removeObject(forKey: revisionKey)

    var value = Config.SystemUserDictionary.default
    value.lastUpdate = .now
    Config.SystemUserDictionary().value = value
    #expect(defaults.integer(forKey: revisionKey) == 0)

    value.items.append(.init(word: "正則列", reading: "せいそくれつ"))
    Config.SystemUserDictionary().value = value
    #expect(defaults.integer(forKey: revisionKey) == 1)
}
