import Foundation
import KanaKanjiConverterModule

enum CustomInputTableStore {
    private static let appSupportSubdir = "azooKeyMac"
    private static let directoryName = "CustomInputTable"
    private static let fileName = "custom_input_table.tsv"

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appSupportSubdir, isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName, conformingTo: .text)
    }

    @discardableResult
    static func save(exported: String) throws -> URL {
        try ensureDirectoryExists()
        let data = Data(exported.utf8)
        try data.write(to: fileURL, options: [.atomic])
        return fileURL
    }

    static func load() -> String? {
        guard exists() else {
            return nil
        }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    static func loadTable() -> InputTable? {
        guard exists() else {
            return nil
        }
        return try? InputStyleManager.loadTable(from: fileURL)
    }

    static func exists() -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    private static func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
