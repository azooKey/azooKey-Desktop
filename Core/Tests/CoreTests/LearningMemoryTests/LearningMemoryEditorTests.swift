@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@Test(arguments: [3, 255])
func learningMemoryEditorDeletesSelectedEntries(count: Int) throws {
    let directoryURL = try learningMemoryEditorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    let converter = KanaKanjiConverter.withDefaultDictionary()
    func candidate(_ ruby: String, _ word: String) -> Candidate {
        Candidate(text: word, value: 0, composingCount: .surfaceCount(0), lastMid: MIDData.一般.mid, data: [
            .init(word: word, ruby: ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: 0)
        ])
    }
    func candidates(_ reading: String) -> [String] {
        var composingText = ComposingText()
        composingText.insertAtCursorPosition(reading, inputStyle: .direct)
        defer { converter.stopComposition() }
        return converter.requestCandidates(composingText, options: .init(
            requireJapanesePrediction: .disabled,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            learningType: .inputAndOutput,
            memoryDirectoryURL: directoryURL,
            sharedContainerURL: CompiledUserDictionaryStore.directoryURL(memoryDirectoryURL: directoryURL),
            textReplacer: .empty,
            specialCandidateProviders: nil,
            metadata: nil
        )).mainResults.map(\.text)
    }

    _ = candidates("あ")
    let initial = [candidate("テスト", "テスト項目"), candidate("テストコウモク", "テスト項目"), candidate("テスト", "テスト候補"), candidate("サンプル", "サンプル"), candidate("テストサクジョ", "削除テスト用候補")]
    for _ in 0 ..< count {
        for entry in initial {
            converter.stopComposition()
            converter.updateLearningData(entry)
        }
    }
    converter.commitUpdateLearningData()
    let learned = try LearningMemoryEditor.load(directoryURL: directoryURL)
    let restoredID = try #require(learned.first { $0.ruby == "テスト" && $0.word == "テスト項目" }).id
    let today = Int(Date().timeIntervalSince1970) / 86400 - 19000
    let metadataURL = directoryURL.appendingPathComponent("memory.memorymetadata")
    var metadata = try Data(contentsOf: metadataURL)
    var offset = 4
    var entryIndex = 0
    while offset < metadata.count {
        let itemCount = Int(metadata[offset])
        offset += 1
        for _ in 0 ..< itemCount {
            if learned[entryIndex].id == restoredID {
                for (index, day) in [today - 7, today - 3].enumerated() {
                    metadata[offset + 2 * index] = UInt8(day & 0xff)
                    metadata[offset + 2 * index + 1] = UInt8(day >> 8)
                }
            }
            entryIndex += 1
            offset += 5
        }
    }
    try metadata.write(to: metadataURL)
    let original = try LearningMemoryEditor.load(directoryURL: directoryURL)
    #expect(original.count == 5)
    #expect(original.allSatisfy { $0.count == count })
    #expect(original.first { $0.id == restoredID }?.lastUsedDay == today - 7)
    #expect(original.first { $0.id == restoredID }?.lastUpdatedDay == today - 3)
    #expect(candidates("てすとさくじょ").contains("削除テスト用候補"))

    let selection = Set(original.filter { ["テストコウモク", "テストサクジョ"].contains($0.ruby) }.map(\.id))
    let plan = LearningMemoryEditor.plan(entries: original, deleting: selection)
    #expect(Set(plan.deleted.map(\.ruby)) == ["テストコウモク", "テストサクジョ"])
    #expect(plan.readded.map(\.ruby) == ["テスト"])

    #expect(try !LearningMemoryEditor.unapplied(plan, directoryURL: directoryURL).isEmpty)
    try LearningMemoryEditor.apply(plan, directoryURL: directoryURL, converter: converter)
    #expect(try LearningMemoryEditor.unapplied(plan, directoryURL: directoryURL).isEmpty)
    let result = try LearningMemoryEditor.load(directoryURL: directoryURL)
    #expect(Set(result.map { "\($0.ruby)/\($0.word)" }) == ["テスト/テスト項目", "テスト/テスト候補", "サンプル/サンプル"])
    #expect(result.first { $0.ruby == "サンプル" } == original.first { $0.ruby == "サンプル" })
    #expect(result.first { $0.id == restoredID } == original.first { $0.id == restoredID })
    #expect(!FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent(".pause").path))
    for name in ["memory.memorymetadata", "memory0.loudstxt3", "memory.loudschars2", "memory.louds"] {
        let url = directoryURL.appendingPathComponent(name)
        #expect(try Data(contentsOf: url) == Data(contentsOf: url.appendingPathExtension("2")))
    }
    #expect(!candidates("てすとさくじょ").contains("削除テスト用候補"))
    converter.stopComposition()
    converter.updateLearningData(candidate("テスト", "テスト項目"))
    converter.commitUpdateLearningData()
    let updated = try #require(LearningMemoryEditor.load(directoryURL: directoryURL).first { $0.id == restoredID })
    #expect(updated.count == min(count + 1, 255))
    #expect(updated.lastUsedDay == today)
    #expect(try LearningMemoryEditor.unapplied(plan, directoryURL: directoryURL).readded.map(\.id) == [restoredID])
}

@Test func learningMemoryEditorSkipsDeletionForEmptySelection() throws {
    let directoryURL = try learningMemoryEditorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    #expect(try LearningMemoryEditor.load(directoryURL: directoryURL).isEmpty)
    let plan = LearningMemoryEditor.plan(entries: [], deleting: [])
    #expect(plan.isEmpty)
    try LearningMemoryEditor.apply(plan, directoryURL: directoryURL, converter: .withDefaultDictionary())
    #expect(try FileManager.default.contentsOfDirectory(atPath: directoryURL.path).isEmpty)
}

@Test(arguments: [
    [UInt8](),
    [1, 0, 0],
    [255, 255, 255, 255],
    [0, 0, 0, 0, 0]
])
func learningMemoryEditorRejectsMalformedMetadata(_ bytes: [UInt8]) throws {
    let directoryURL = try learningMemoryEditorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try Data(bytes).write(to: directoryURL.appendingPathComponent("memory.memorymetadata"))
    #expect(throws: LearningMemoryEditor.EditorError.self) {
        try LearningMemoryEditor.load(directoryURL: directoryURL)
    }
}

@Test(arguments: [
    [UInt8](),
    [1],
    [0, 0],
    [1, 0],
    [1, 0, 0, 0, 0, 0, 0, 0],
    [1, 0, 255, 255, 255, 255, 0, 0],
    [1, 0, 6, 0, 0, 0, 1, 0],
    [2, 0, 10, 0, 0, 0, 12, 0, 0, 0, 0, 0, 0, 0]
])
func learningMemoryEditorRejectsMalformedShards(_ bytes: [UInt8]) throws {
    let directoryURL = try learningMemoryEditorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try Data([1, 0, 0, 0, 0]).write(to: directoryURL.appendingPathComponent("memory.memorymetadata"))
    try Data(bytes).write(to: directoryURL.appendingPathComponent("memory0.loudstxt3"))
    #expect(throws: LearningMemoryEditor.EditorError.self) {
        try LearningMemoryEditor.load(directoryURL: directoryURL)
    }
}

@Test func learningMemoryEditorRejectsIncompleteSave() throws {
    let directoryURL = try learningMemoryEditorTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directoryURL) }
    try Data().write(to: directoryURL.appendingPathComponent(".pause"))
    #expect(throws: LearningMemoryEditor.EditorError.self) {
        try LearningMemoryEditor.load(directoryURL: directoryURL)
    }
}

private func learningMemoryEditorTemporaryDirectory() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL
}
