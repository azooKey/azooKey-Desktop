@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@Test func rebuildCompiledUserDictionaryWritesSearchFiles() throws {
    let directoryURL = try makeTemporaryDirectoryURL()
    let charIDFileURL = try makeTemporaryCharIDFileURL(characters: "\0テストジショ")
    let entries = [
        DicdataElement(word: "テスト単語", ruby: "テスト", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5),
        DicdataElement(word: "辞書単語", ruby: "ジショ", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    ]

    try CompiledUserDictionaryStore.rebuild(entries: entries, directoryURL: directoryURL, charIDFileURL: charIDFileURL)

    #expect(CompiledUserDictionaryStore.hasCompiledDictionary(at: directoryURL))
    #expect(!FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("metadata.json").path))
    #expect(!FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("fallback.json").path))
}

@Test func rebuildCompiledUserDictionarySkipsUnsupportedReadings() throws {
    let directoryURL = try makeTemporaryDirectoryURL()
    let charIDFileURL = try makeTemporaryCharIDFileURL(characters: "\0テスト")
    let entries = [
        DicdataElement(word: "外字単語", ruby: "\u{10FFFF}", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    ]

    try CompiledUserDictionaryStore.rebuild(entries: entries, directoryURL: directoryURL, charIDFileURL: charIDFileURL)

    #expect(!CompiledUserDictionaryStore.hasCompiledDictionary(at: directoryURL))
    #expect(!FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("metadata.json").path))
    #expect(!FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent("fallback.json").path))
}

@MainActor
@Test func compiledUserDictionaryCandidatesUseExportDirectory() throws {
    guard CompiledUserDictionaryStore.defaultCharIDFileURL() != nil else {
        return
    }
    let memoryURL = try makeTemporaryDirectoryURL()
    let dictionaryURL = CompiledUserDictionaryStore.directoryURL(memoryDirectoryURL: memoryURL)
    try CompiledUserDictionaryStore.rebuild(entries: [
        DicdataElement(word: "コーシー", ruby: "コーシー", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5),
        DicdataElement(word: "Cauchy", ruby: "コーシー", cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
    ], directoryURL: dictionaryURL)

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

private func makeTemporaryCharIDFileURL(characters: String) throws -> URL {
    let directoryURL = try makeTemporaryDirectoryURL()
    let fileURL = directoryURL.appendingPathComponent("charID.chid", isDirectory: false)
    try characters.write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL
}
