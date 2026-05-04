import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

public struct UserDictionaryIndexBuildResult: Sendable, Equatable {
    public var indexedEntryCount: Int
    public var skippedEntryCount: Int
    public var totalEntryCount: Int
}

public struct UserDictionaryIndexSummary: Sendable, Equatable {
    public var userRevision: Int
    public var systemRevision: Int
    public var indexedEntryCount: Int
    public var skippedEntryCount: Int
    public var totalEntryCount: Int
    public var updatedAt: Date?
}

public enum UserDictionaryIndexStatus: Sendable, Equatable {
    case notBuilt(entryCount: Int)
    case ready(UserDictionaryIndexSummary)
    case needsRebuild(currentEntryCount: Int, existing: UserDictionaryIndexSummary?)
}

public enum UserDictionaryIndexController {
    public static func indexDirectoryURL(applicationDirectoryURL: URL) -> URL {
        applicationDirectoryURL.appendingPathComponent("UserDictionary", isDirectory: true)
    }

    public static func currentStatus(applicationDirectoryURL: URL) -> UserDictionaryIndexStatus {
        Self.status(
            directoryURL: Self.indexDirectoryURL(applicationDirectoryURL: applicationDirectoryURL),
            currentUserRevision: UserDefaults.standard.integer(forKey: Config.UserDictionary.revisionKey),
            currentSystemRevision: UserDefaults.standard.integer(forKey: Config.SystemUserDictionary.revisionKey),
            entryCount: Self.currentEntries().count
        )
    }

    public static func rebuild(applicationDirectoryURL: URL) throws -> UserDictionaryIndexBuildResult {
        let entries = Self.currentEntries()
        let result = try UserDictionaryIndexStore(
            directoryURL: Self.indexDirectoryURL(applicationDirectoryURL: applicationDirectoryURL)
        ).rebuild(
            entries: entries,
            userRevision: UserDefaults.standard.integer(forKey: Config.UserDictionary.revisionKey),
            systemRevision: UserDefaults.standard.integer(forKey: Config.SystemUserDictionary.revisionKey)
        )
        return .init(
            indexedEntryCount: result.indexedEntryCount,
            skippedEntryCount: result.skippedEntryCount,
            totalEntryCount: entries.count
        )
    }

    static func status(
        directoryURL: URL,
        currentUserRevision: Int,
        currentSystemRevision: Int,
        entryCount: Int
    ) -> UserDictionaryIndexStatus {
        let store = UserDictionaryIndexStore(directoryURL: directoryURL)
        guard let metadata = store.metadata() else {
            return .notBuilt(entryCount: entryCount)
        }
        let summary = UserDictionaryIndexSummary(
            userRevision: metadata.userRevision,
            systemRevision: metadata.systemRevision,
            indexedEntryCount: metadata.indexedEntryCount,
            skippedEntryCount: metadata.skippedEntryCount,
            totalEntryCount: metadata.indexedEntryCount + metadata.skippedEntryCount,
            updatedAt: Self.metadataModificationDate(directoryURL: directoryURL)
        )
        if metadata.userRevision == currentUserRevision,
           metadata.systemRevision == currentSystemRevision,
           store.hasUsableIndex(for: metadata) {
            return .ready(summary)
        }
        return .needsRebuild(currentEntryCount: entryCount, existing: summary)
    }

    private static func currentEntries() -> [DicdataElement] {
        let userEntries = Config.UserDictionary().value.enabledItems.map { item in
            let ruby = item.reading.toKatakana()
            return DicdataElement(word: item.word, ruby: ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
        }
        let systemEntries = Config.SystemUserDictionary().value.items.map { item in
            let ruby = item.reading.toKatakana()
            return DicdataElement(word: item.word, ruby: ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
        }
        return userEntries + systemEntries
    }

    private static func metadataModificationDate(directoryURL: URL) -> Date? {
        let metadataURL = directoryURL.appendingPathComponent("metadata.json", isDirectory: false)
        let attributes = try? FileManager.default.attributesOfItem(atPath: metadataURL.path)
        return attributes?[.modificationDate] as? Date
    }
}

struct UserDictionaryIndexStore {
    enum BuildError: Error {
        case missingCharIDFile
    }

    struct RebuildResult {
        var indexedEntryCount: Int
        var skippedEntryCount: Int
    }

    struct Metadata: Codable, Equatable {
        var userRevision: Int
        var systemRevision: Int
        var indexedEntryCount: Int
        var skippedEntryCount: Int
    }

    let directoryURL: URL

    private var metadataURL: URL {
        directoryURL.appendingPathComponent("metadata.json", isDirectory: false)
    }

    func metadata() -> Metadata? {
        guard let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }

    func hasUsableIndex(for metadata: Metadata) -> Bool {
        guard metadata.indexedEntryCount > 0 else {
            return true
        }
        let requiredFileNames = [
            "user.louds",
            "user.loudschars2",
            "user0.loudstxt3"
        ]
        return requiredFileNames.allSatisfy {
            FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent($0, isDirectory: false).path)
        }
    }

    func rebuild(entries: [DicdataElement], userRevision: Int, systemRevision: Int) throws -> RebuildResult {
        let fileManager = FileManager.default
        let parentURL = directoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let temporaryURL = parentURL.appendingPathComponent(
            "\(directoryURL.lastPathComponent).building-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        do {
            let indexableEntries: [DicdataElement]
            if entries.isEmpty {
                indexableEntries = []
            } else {
                guard let charIDFileURL = Self.defaultCharIDFileURL() else {
                    throw BuildError.missingCharIDFile
                }
                let supportedCharacters = try Self.supportedCharacters(from: charIDFileURL)
                indexableEntries = entries.filter {
                    Self.canIndex(ruby: $0.ruby, supportedCharacters: supportedCharacters)
                }
                guard !indexableEntries.isEmpty else {
                    if fileManager.fileExists(atPath: directoryURL.path) {
                        try fileManager.removeItem(at: directoryURL)
                    }
                    try Self.writeMetadata(
                        .init(userRevision: userRevision, systemRevision: systemRevision, indexedEntryCount: 0, skippedEntryCount: entries.count),
                        to: temporaryURL
                    )
                    try fileManager.moveItem(at: temporaryURL, to: directoryURL)
                    return .init(indexedEntryCount: 0, skippedEntryCount: entries.count)
                }
                try DictionaryBuilder.exportDictionary(
                    entries: indexableEntries,
                    to: temporaryURL,
                    baseName: "user",
                    shardByFirstCharacter: false,
                    charIDFileURL: charIDFileURL
                )
            }

            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            let result = RebuildResult(indexedEntryCount: indexableEntries.count, skippedEntryCount: entries.count - indexableEntries.count)
            try Self.writeMetadata(
                .init(
                    userRevision: userRevision,
                    systemRevision: systemRevision,
                    indexedEntryCount: result.indexedEntryCount,
                    skippedEntryCount: result.skippedEntryCount
                ),
                to: temporaryURL
            )
            try fileManager.moveItem(at: temporaryURL, to: directoryURL)
            return result
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func supportedCharacters() throws -> Set<Character> {
        guard let charIDFileURL = Self.defaultCharIDFileURL() else {
            throw BuildError.missingCharIDFile
        }
        return try Self.supportedCharacters(from: charIDFileURL)
    }

    static func canIndex(ruby: String, supportedCharacters: Set<Character>) -> Bool {
        !ruby.isEmpty && ruby.allSatisfy { supportedCharacters.contains($0) }
    }

    private static func defaultCharIDFileURL() -> URL? {
        _ = DicdataStore.withDefaultDictionary(preloadDictionary: false)
        return (Bundle.allBundles + Bundle.allFrameworks)
            .lazy
            .compactMap(\.resourceURL)
            .map {
                $0.appendingPathComponent("Dictionary/louds/charID.chid", isDirectory: false)
            }
            .first {
                FileManager.default.fileExists(atPath: $0.path)
            }
    }

    private static func supportedCharacters(from charIDFileURL: URL) throws -> Set<Character> {
        let text = try String(contentsOf: charIDFileURL, encoding: .utf8)
        return Set(text)
    }

    private static func writeMetadata(_ metadata: Metadata, to directoryURL: URL) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: directoryURL.appendingPathComponent("metadata.json", isDirectory: false))
    }
}
