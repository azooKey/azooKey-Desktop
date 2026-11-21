#if os(macOS)
import Foundation

public enum LegacyDataMigration {
    public static let appGroupIdentifier = "group.dev.ensan.inputmethod.azooKeyMac"

    public enum LearningStatus {
        case missing
        case keptCurrent
        case staged
    }

    private static let learningFiles = ["memory.louds", "memory.loudschars2", "memory.memorymetadata"]
    private static let replacementMarker = ".replace-current-learning"

    public static func readUserDictionary(from preferencesURL: URL) throws -> Config.UserDictionary.Value? {
        let data: Data
        do {
            data = try Data(contentsOf: preferencesURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
        guard let preferences = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let value = preferences[Config.UserDictionary.key] else {
            return nil
        }
        guard let dictionary = value as? Data else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try JSONDecoder().decode(Config.UserDictionary.Value.self, from: dictionary)
    }

    public static func mergeUserDictionary(
        _ legacy: Config.UserDictionary.Value,
        into current: Config.UserDictionary.Value
    ) -> Config.UserDictionary.Value {
        var merged = current
        var ids = Set(current.items.map(\.id))
        for var entry in legacy.items where !entry.word.isEmpty && !entry.reading.isEmpty {
            guard !merged.items.contains(where: { $0.word == entry.word && $0.reading == entry.reading }) else {
                continue
            }
            if !ids.insert(entry.id).inserted {
                entry.id = UUID()
                ids.insert(entry.id)
            }
            merged.items.append(entry)
        }
        return merged
    }

    public static func stageLearning(from source: URL, for destination: URL, replacingCurrent: Bool = false) throws -> LearningStatus {
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            return .missing
        }
        let fileManager = FileManager.default
        let sourceFiles = try Self.learningFileURLs(in: source)
        guard !sourceFiles.isEmpty else {
            return .missing
        }
        guard try replacingCurrent || Self.learningFileURLs(in: destination).isEmpty else {
            return .keptCurrent
        }

        let pending = Self.pendingLearningURL(for: destination)

        // If the old converter was interrupted during a save, only the .2 files form a complete snapshot.
        let suffix = sourceFiles.contains { $0.lastPathComponent == ".pause" } ? ".2" : ""
        let snapshot = sourceFiles.filter { url in
            let name = url.lastPathComponent
            return name != ".pause" && (suffix.isEmpty ? !name.hasSuffix(".2") : name.hasSuffix(suffix))
        }
        let names = snapshot.map { String($0.lastPathComponent.dropLast(suffix.count)) }
        guard Set(Self.learningFiles + ["memory0.loudstxt3"]).isSubset(of: names) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let temporary = pending.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporary) }

        for (url, name) in zip(snapshot, names) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try fileManager.copyItem(at: url, to: temporary.appendingPathComponent(name))
        }
        if replacingCurrent {
            try Data().write(to: temporary.appendingPathComponent(Self.replacementMarker))
        }
        if fileManager.fileExists(atPath: pending.path) {
            _ = try fileManager.replaceItemAt(pending, withItemAt: temporary, options: .usingNewMetadataOnly)
        } else {
            try fileManager.moveItem(at: temporary, to: pending)
        }
        return .staged
    }

    /// Apply the staged snapshot before the converter starts reading or writing the destination.
    public static func applyStagedLearning(to destination: URL) throws {
        let fileManager = FileManager.default
        let pending = Self.pendingLearningURL(for: destination)
        guard fileManager.fileExists(atPath: pending.path) else {
            return
        }
        let currentFiles = try Self.learningFileURLs(in: destination)
        let replacingCurrent = fileManager.fileExists(atPath: pending.appendingPathComponent(Self.replacementMarker).path)
        guard currentFiles.isEmpty || replacingCurrent else {
            // The converter saved new learning after the import was requested.
            try Self.discardStagedLearning(for: destination)
            return
        }
        if !replacingCurrent, !fileManager.fileExists(atPath: destination.path) {
            try fileManager.moveItem(at: pending, to: destination)
            return
        }

        let replacement = pending.deletingLastPathComponent().appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: replacement) }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.copyItem(at: destination, to: replacement)
        } else {
            try fileManager.createDirectory(at: replacement, withIntermediateDirectories: false)
        }
        for file in currentFiles {
            try fileManager.removeItem(at: replacement.appendingPathComponent(file.lastPathComponent))
        }
        for file in try Self.learningFileURLs(in: pending) {
            try fileManager.copyItem(at: file, to: replacement.appendingPathComponent(file.lastPathComponent))
        }
        if fileManager.fileExists(atPath: destination.path) {
            let backup = currentFiles.isEmpty ? nil : "memory-backup-\(UUID().uuidString)"
            _ = try fileManager.replaceItemAt(
                destination, withItemAt: replacement, backupItemName: backup,
                options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
            )
        } else {
            try fileManager.moveItem(at: replacement, to: destination)
        }
        try Self.discardStagedLearning(for: destination)
    }

    public static func discardStagedLearning(for destination: URL) throws {
        let pending = Self.pendingLearningURL(for: destination)
        if FileManager.default.fileExists(atPath: pending.path) {
            try FileManager.default.removeItem(at: pending)
        }
    }

    private static func pendingLearningURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(".legacy-learning-import", isDirectory: true)
    }

    private static func learningFileURLs(in directory: URL) throws -> [URL] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        return files.filter { file in
            let name = file.lastPathComponent
            if name == ".pause" {
                return true
            }
            let base = name.hasSuffix(".2") ? String(name.dropLast(2)) : name
            return Self.learningFiles.contains(base) || base.range(of: #"^memory[0-9]+\.loudstxt3$"#, options: .regularExpression) != nil
        }
    }
}
#endif
