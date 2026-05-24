import Foundation

public enum AppGroup {
    public static let azooKeyMacIdentifier = "group.dev.ensan.inputmethod.azooKeyMac"

    #if os(macOS)
    public static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.azooKeyMacIdentifier)
    }

    public static func applicationSupportDirectoryURL(fileManager: FileManager = .default) -> URL {
        if let containerURL = Self.containerURL(fileManager: fileManager) {
            return containerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("azooKey", isDirectory: true)
        }

        if #available(macOS 13, *) {
            return URL.applicationSupportDirectory
                .appending(path: "azooKey", directoryHint: .isDirectory)
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("azooKey", isDirectory: true)
    }

    public static func memoryDirectoryURL(fileManager: FileManager = .default) -> URL {
        Self.applicationSupportDirectoryURL(fileManager: fileManager)
            .appendingPathComponent("memory", isDirectory: true)
    }
    #endif
}
