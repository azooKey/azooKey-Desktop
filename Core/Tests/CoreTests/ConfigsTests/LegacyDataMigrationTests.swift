#if os(macOS)
@testable import Core
import Foundation
import Testing

@Suite("LegacyDataMigration")
struct LegacyDataMigrationTests {
    private static let snapshotFiles = ["memory.louds", "memory.loudschars2", "memory.memorymetadata", "memory0.loudstxt3"]

    @Test func importsLearningAndKeepsCompiledUserDictionary() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("old-memory")
        let destination = root.appendingPathComponent("new-memory")
        let dictionary = destination.appendingPathComponent("UserDictionary/user.louds")
        try FileManager.default.createDirectory(at: dictionary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([4]).write(to: dictionary)
        try Self.writeSnapshot(at: source, byte: 1)
        try Data([2]).write(to: source.appendingPathComponent("unrelated"))

        #expect(try LegacyDataMigration.stageLearning(from: source, for: destination) == .staged)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("memory.louds").path))
        try LegacyDataMigration.applyStagedLearning(to: destination)
        try LegacyDataMigration.applyStagedLearning(to: destination)

        for name in Self.snapshotFiles {
            #expect(try Data(contentsOf: destination.appendingPathComponent(name)) == Data([1]))
            #expect(try Data(contentsOf: source.appendingPathComponent(name)) == Data([1]))
        }
        #expect(try Data(contentsOf: dictionary) == Data([4]))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("unrelated").path))
    }

    @Test func keepsLearningSavedAfterStaging() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("old-memory")
        let destination = root.appendingPathComponent("new-memory")
        try Self.writeSnapshot(at: source, byte: 1)
        #expect(try LegacyDataMigration.stageLearning(from: source, for: destination) == .staged)
        try Self.writeSnapshot(at: destination, byte: 2)
        #expect(try LegacyDataMigration.stageLearning(from: source, for: destination) == .keptCurrent)

        try LegacyDataMigration.applyStagedLearning(to: destination)
        for name in Self.snapshotFiles {
            #expect(try Data(contentsOf: destination.appendingPathComponent(name)) == Data([2]))
        }

        try FileManager.default.removeItem(at: destination)
        try LegacyDataMigration.applyStagedLearning(to: destination)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func restoresCompleteTemporaryFilesFromInterruptedSave() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("old-memory")
        let destination = root.appendingPathComponent("new-memory")
        try Self.writeSnapshot(at: source, byte: 1)
        try Self.writeSnapshot(at: source, byte: 2, suffix: ".2")
        try Data().write(to: source.appendingPathComponent(".pause"))
        let temporaryShard = source.appendingPathComponent("memory0.loudstxt3.2")
        try FileManager.default.removeItem(at: temporaryShard)

        #expect(throws: CocoaError.self) {
            try LegacyDataMigration.stageLearning(from: source, for: destination)
        }
        try LegacyDataMigration.applyStagedLearning(to: destination)
        #expect(!FileManager.default.fileExists(atPath: destination.path))

        try Data([2]).write(to: temporaryShard)
        #expect(try LegacyDataMigration.stageLearning(from: source, for: destination) == .staged)
        try LegacyDataMigration.applyStagedLearning(to: destination)
        for name in Self.snapshotFiles {
            #expect(try Data(contentsOf: destination.appendingPathComponent(name)) == Data([2]))
        }
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent(".pause").path))
    }

    @Test func backsUpCurrentLearningWhenReplacementIsRequested() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("old-memory")
        let destination = root.appendingPathComponent("new-memory")
        try Self.writeSnapshot(at: source, byte: 1)
        try Self.writeSnapshot(at: destination, byte: 2)

        #expect(try LegacyDataMigration.stageLearning(from: source, for: destination, replacingCurrent: true) == .staged)
        try LegacyDataMigration.applyStagedLearning(to: destination)

        let backup = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first {
            $0.lastPathComponent.hasPrefix("memory-backup-")
        })
        for name in Self.snapshotFiles {
            #expect(try Data(contentsOf: destination.appendingPathComponent(name)) == Data([1]))
            #expect(try Data(contentsOf: backup.appendingPathComponent(name)) == Data([2]))
        }
    }

    @Test func importsDictionaryFromSharedPreferencesWithoutDuplicates() throws {
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let preferences = root.appendingPathComponent("legacy.plist")
        let entry = Config.UserDictionaryEntry(word: "登録済み", reading: "とうろくずみ", hint: "現在")
        var editedEntry = entry
        editedEntry.word = "旧版の単語"
        var duplicate = entry
        duplicate.nonNullHint = "旧版"
        let old: Config.UserDictionary.Value = .init(items: [duplicate, editedEntry])
        let data = try PropertyListSerialization.data(
            fromPropertyList: [Config.UserDictionary.key: JSONEncoder().encode(old)],
            format: .binary,
            options: 0
        )
        try data.write(to: preferences)

        let decoded = try LegacyDataMigration.readUserDictionary(from: preferences)
        let imported = try #require(decoded)
        let merged = LegacyDataMigration.mergeUserDictionary(imported, into: .init(items: [entry]))
        #expect(merged.items.map(\.word) == [entry.word, editedEntry.word])
        #expect(merged.items[0].nonNullHint == "現在")
        #expect(Set(merged.items.map(\.id)).count == 2)
        #expect(LegacyDataMigration.mergeUserDictionary(imported, into: merged).items.count == 2)
    }

    private static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writeSnapshot(at url: URL, byte: UInt8, suffix: String = "") throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for name in Self.snapshotFiles {
            try Data([byte]).write(to: url.appendingPathComponent(name + suffix))
        }
    }
}
#endif
