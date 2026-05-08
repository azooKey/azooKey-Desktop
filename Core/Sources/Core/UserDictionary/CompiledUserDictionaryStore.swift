import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

public struct CompiledUserDictionaryExportResult: Sendable, Equatable {
    public var indexedEntryCount: Int
    public var fallbackEntryCount: Int
    public var totalEntryCount: Int
}

public enum CompiledUserDictionaryStore {
    public static func directoryURL(memoryDirectoryURL: URL) -> URL {
        memoryDirectoryURL.appendingPathComponent("UserDictionary", isDirectory: true)
    }

    public static func exportCurrentDictionaries(memoryDirectoryURL: URL) throws -> CompiledUserDictionaryExportResult {
        let entries = Self.currentEntries()
        return try UserDictionaryIndexStore(
            directoryURL: Self.directoryURL(memoryDirectoryURL: memoryDirectoryURL)
        ).rebuild(entries: entries)
    }

    public static func fallbackEntries(memoryDirectoryURL: URL) -> [DicdataElement] {
        UserDictionaryIndexStore(
            directoryURL: Self.directoryURL(memoryDirectoryURL: memoryDirectoryURL)
        ).fallbackEntries()
    }

    public static func modificationDate(memoryDirectoryURL: URL) -> Date? {
        let metadataURL = Self.directoryURL(memoryDirectoryURL: memoryDirectoryURL)
            .appendingPathComponent("metadata.json", isDirectory: false)
        let attributes = try? FileManager.default.attributesOfItem(atPath: metadataURL.path)
        return attributes?[.modificationDate] as? Date
    }

    private static func currentEntries() -> [DicdataElement] {
        let userEntries = Config.UserDictionary().value.items.map { item in
            let ruby = item.reading.toKatakana()
            return DicdataElement(word: item.word, ruby: ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
        }
        let systemEntries = Config.SystemUserDictionary().value.items.map { item in
            let ruby = item.reading.toKatakana()
            return DicdataElement(word: item.word, ruby: ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
        }
        return userEntries + systemEntries
    }
}

struct UserDictionaryIndexStore {
    enum BuildError: Error {
        case missingCharIDFile
    }

    struct Metadata: Codable, Equatable {
        var indexedEntryCount: Int
        var fallbackEntryCount: Int
    }

    private struct FallbackEntry: Codable, Equatable {
        var word: String
        var ruby: String
    }

    let directoryURL: URL

    private var metadataURL: URL {
        directoryURL.appendingPathComponent("metadata.json", isDirectory: false)
    }

    private var fallbackURL: URL {
        directoryURL.appendingPathComponent("fallback.json", isDirectory: false)
    }

    func metadata() -> Metadata? {
        guard let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }

    func hasCompiledDictionary() -> Bool {
        let requiredFileNames = [
            "user.louds",
            "user.loudschars2",
            "user0.loudstxt3"
        ]
        return requiredFileNames.allSatisfy {
            FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent($0, isDirectory: false).path)
        }
    }

    func fallbackEntries() -> [DicdataElement] {
        guard let data = try? Data(contentsOf: fallbackURL),
              let entries = try? JSONDecoder().decode([FallbackEntry].self, from: data) else {
            return []
        }
        return entries.map {
            DicdataElement(word: $0.word, ruby: $0.ruby, cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid, value: -5)
        }
    }

    @discardableResult
    func rebuild(entries: [DicdataElement]) throws -> CompiledUserDictionaryExportResult {
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
            let fallbackEntries: [DicdataElement]
            if entries.isEmpty {
                indexableEntries = []
                fallbackEntries = []
            } else {
                guard let charIDFileURL = Self.defaultCharIDFileURL() else {
                    throw BuildError.missingCharIDFile
                }
                let supportedCharacters = try Self.supportedCharacters(from: charIDFileURL)
                indexableEntries = entries.filter {
                    Self.canIndex(ruby: $0.ruby, supportedCharacters: supportedCharacters)
                }
                fallbackEntries = entries.filter {
                    !Self.canIndex(ruby: $0.ruby, supportedCharacters: supportedCharacters)
                }
                if !indexableEntries.isEmpty {
                    try DictionaryBuilder.exportDictionary(
                        entries: indexableEntries,
                        to: temporaryURL,
                        baseName: "user",
                        shardByFirstCharacter: false,
                        charIDFileURL: charIDFileURL
                    )
                }
            }

            try Self.writeFallbackEntries(fallbackEntries, to: temporaryURL)
            try Self.writeMetadata(
                .init(indexedEntryCount: indexableEntries.count, fallbackEntryCount: fallbackEntries.count),
                to: temporaryURL
            )
            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: directoryURL)
            return .init(
                indexedEntryCount: indexableEntries.count,
                fallbackEntryCount: fallbackEntries.count,
                totalEntryCount: entries.count
            )
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
        let fileManager = FileManager.default
        var resourceURLs = (Bundle.allBundles + Bundle.allFrameworks).compactMap(\.resourceURL)

        if let mainResourceURL = Bundle.main.resourceURL,
           let enumerator = fileManager.enumerator(
            at: mainResourceURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
           ) {
            for case let url as URL in enumerator where url.pathExtension == "bundle" {
                if let bundle = Bundle(url: url), let resourceURL = bundle.resourceURL {
                    resourceURLs.append(resourceURL)
                } else {
                    resourceURLs.append(url.appendingPathComponent("Contents/Resources", isDirectory: true))
                }
            }
        }

        return resourceURLs.lazy
            .map {
                $0.appendingPathComponent("Dictionary/louds/charID.chid", isDirectory: false)
            }
            .first {
                fileManager.fileExists(atPath: $0.path)
            }
    }

    private static func supportedCharacters(from charIDFileURL: URL) throws -> Set<Character> {
        let text = try String(contentsOf: charIDFileURL, encoding: .utf8)
        return Set(text)
    }

    private static func writeFallbackEntries(_ entries: [DicdataElement], to directoryURL: URL) throws {
        let fallbackEntries = entries.map {
            FallbackEntry(word: $0.word, ruby: $0.ruby)
        }
        let data = try JSONEncoder().encode(fallbackEntries)
        try data.write(to: directoryURL.appendingPathComponent("fallback.json", isDirectory: false))
    }

    private static func writeMetadata(_ metadata: Metadata, to directoryURL: URL) throws {
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: directoryURL.appendingPathComponent("metadata.json", isDirectory: false))
    }
}
