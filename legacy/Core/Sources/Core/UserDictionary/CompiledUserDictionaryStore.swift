import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

public enum CompiledUserDictionaryStore {
    enum BuildError: Error {
        case missingCharIDFile
    }

    public static func directoryURL(memoryDirectoryURL: URL) -> URL {
        memoryDirectoryURL.appendingPathComponent("UserDictionary", isDirectory: true)
    }

    public static func exportCurrentDictionaries(memoryDirectoryURL: URL) throws {
        try Self.rebuild(
            entries: Self.currentEntries(),
            directoryURL: Self.directoryURL(memoryDirectoryURL: memoryDirectoryURL)
        )
    }

    public static func hasExportedDictionary(memoryDirectoryURL: URL) -> Bool {
        Self.hasCompiledDictionary(at: Self.directoryURL(memoryDirectoryURL: memoryDirectoryURL))
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

    static func hasCompiledDictionary(at directoryURL: URL) -> Bool {
        ["user.louds", "user.loudschars2", "user0.loudstxt3"].allSatisfy {
            FileManager.default.fileExists(atPath: directoryURL.appendingPathComponent($0, isDirectory: false).path)
        }
    }

    static func rebuild(entries: [DicdataElement], directoryURL: URL, charIDFileURL: URL? = nil) throws {
        let fileManager = FileManager.default
        let parentURL = directoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let temporaryURL = parentURL.appendingPathComponent(
            "\(directoryURL.lastPathComponent).building-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: temporaryURL, withIntermediateDirectories: true)

        do {
            if !entries.isEmpty {
                guard let charIDFileURL = charIDFileURL ?? Self.defaultCharIDFileURL() else {
                    throw BuildError.missingCharIDFile
                }
                let supportedCharacters = Set(try String(contentsOf: charIDFileURL, encoding: .utf8))
                let indexableEntries = entries.filter {
                    !$0.ruby.isEmpty && $0.ruby.allSatisfy(supportedCharacters.contains)
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

            if fileManager.fileExists(atPath: directoryURL.path) {
                try fileManager.removeItem(at: directoryURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: directoryURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func defaultCharIDFileURL() -> URL? {
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
}
