@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@Test func rebuildCompiledUserDictionaryWritesSearchFiles() throws {
    let directoryURL = try makeTemporaryDirectoryURL()
    let store = UserDictionaryIndexStore(directoryURL: directoryURL)
    let entries = [
        DicdataElement(word: "テスト単語", ruby: "テスト", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5),
        DicdataElement(word: "辞書単語", ruby: "ジショ", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    ]

    let result = try store.rebuild(entries: entries)

    #expect(result.indexedEntryCount == 2)
    #expect(result.fallbackEntryCount == 0)
    #expect(result.totalEntryCount == 2)
    #expect(store.hasCompiledDictionary())
    #expect(FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("metadata.json").path))
    #expect(store.metadata() == .init(indexedEntryCount: 2, fallbackEntryCount: 0))
    #expect(store.fallbackEntries().isEmpty)
}

@Test func rebuildCompiledUserDictionaryStoresUnsupportedReadingsAsFallback() throws {
    let directoryURL = try makeTemporaryDirectoryURL()
    let store = UserDictionaryIndexStore(directoryURL: directoryURL)
    let entries = [
        DicdataElement(word: "外字単語", ruby: "\u{10FFFF}", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    ]

    let result = try store.rebuild(entries: entries)
    let fallbackEntries = store.fallbackEntries()

    #expect(result.indexedEntryCount == 0)
    #expect(result.fallbackEntryCount == 1)
    #expect(result.totalEntryCount == 1)
    #expect(!store.hasCompiledDictionary())
    #expect(fallbackEntries.map(\.word) == ["外字単語"])
    #expect(fallbackEntries.map(\.ruby) == ["\u{10FFFF}"])
}

@Test func userDictionaryIndexabilityUsesDefaultCharIDCharacters() throws {
    let supportedCharacters = try UserDictionaryIndexStore.supportedCharacters()

    #expect(UserDictionaryIndexStore.canIndex(ruby: "テスト", supportedCharacters: supportedCharacters))
    #expect(!UserDictionaryIndexStore.canIndex(ruby: "", supportedCharacters: supportedCharacters))
    #expect(!UserDictionaryIndexStore.canIndex(ruby: "\u{10FFFF}", supportedCharacters: supportedCharacters))
}

@Test func fallbackDynamicUserDictionaryFilteringKeepsRelevantReadings() {
    #expect(SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "コウエン", for: "コウ"))
    #expect(SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "コウ", for: "コウエン"))
    #expect(SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "エン", for: "コウエン"))
    #expect(!SegmentsManager.shouldIncludeDynamicUserDictionaryEntry(ruby: "スウガク", for: "カガク"))
}

@MainActor
@Test func compiledUserDictionaryCandidatesUseExportDirectory() throws {
    let memoryURL = try makeTemporaryDirectoryURL()
    let dictionaryURL = CompiledUserDictionaryStore.directoryURL(memoryDirectoryURL: memoryURL)
    let store = UserDictionaryIndexStore(directoryURL: dictionaryURL)
    try store.rebuild(entries: [
        DicdataElement(word: "コーシー", ruby: "コーシー", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5),
        DicdataElement(word: "Cauchy", ruby: "コーシー", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    ])

    let manager = SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: memoryURL,
        containerURL: nil,
        context: .init(useZenzai: false)
    )
    manager.insertAtCursorPosition("こーしー", inputStyle: .direct)
    manager.requestSetCandidateWindowState(visible: true)

    switch manager.getCurrentCandidateWindow(inputState: .selecting) {
    case .selecting(let candidates, _), .composing(let candidates, _):
        let candidateTexts = candidates.map(\.text)
        #expect(candidateTexts.contains("コーシー"))
        #expect(candidateTexts.contains("Cauchy"))
    case .hidden:
        Issue.record("candidate window is hidden")
    }
}

private func makeTemporaryDirectoryURL() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("CompiledUserDictionaryStoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}
