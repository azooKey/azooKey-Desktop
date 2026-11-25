import Foundation

public enum AppGroup {
    public static let azooKeyMacIdentifier = "group.com.azookey.mac"

    #if os(macOS)
    public static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.azooKeyMacIdentifier)
            ?? Self.containerURL(homeDirectoryURL: fileManager.homeDirectoryForCurrentUser)
    }

    /// App Group APIが利用できない環境で参照する共有コンテナのURLを組み立てる。
    public static func containerURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(Self.azooKeyMacIdentifier, isDirectory: true)
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
