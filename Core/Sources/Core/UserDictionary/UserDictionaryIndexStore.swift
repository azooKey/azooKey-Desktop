import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

struct UserDictionaryIndexStore {
    enum BuildError: Error {
        case missingCharIDFile
    }

    let directoryURL: URL

    func rebuild(entries: [DicdataElement]) throws {
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
                guard let charIDFileURL = Self.defaultCharIDFileURL() else {
                    throw BuildError.missingCharIDFile
                }
                try DictionaryBuilder.exportDictionary(
                    entries: entries,
                    to: temporaryURL,
                    baseName: "user",
                    shardByFirstCharacter: false,
                    charIDFileURL: charIDFileURL
                )
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
}
