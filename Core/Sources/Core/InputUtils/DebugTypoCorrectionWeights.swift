import Crypto
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ZIPFoundation

public enum DebugTypoCorrectionState: Sendable, Equatable {
    case downloaded
    case failed
    case notDownloaded
}

public enum DebugTypoCorrectionWeightsError: LocalizedError, Sendable {
    case invalidHTTPStatus(url: URL, statusCode: Int)
    case hashMismatch(fileName: String, expected: String, actual: String)
    case extractedFolderNotFound(path: String)

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPStatus(let url, let statusCode):
            return "Failed to download \(url.lastPathComponent) (HTTP \(statusCode))"
        case .hashMismatch(let fileName, let expected, let actual):
            return "Hash mismatch for \(fileName). expected=\(expected), actual=\(actual)"
        case .extractedFolderNotFound(let path):
            return "Extracted folder not found at \(path)"
        }
    }
}

public enum DebugTypoCorrectionWeights {
    public struct RequiredFile: Sendable, Equatable {
        public let fileName: String
        public let md5: String
    }

    public static let bundleDirectoryName = "input_n5_lm_v1"

    public static let requiredFiles: [RequiredFile] = [
        .init(fileName: "lm_c_abc.marisa", md5: "cb0c5c156eae8b16e9ddd0757d029263"),
        .init(fileName: "lm_c_bc.marisa", md5: "49a68be03c58d67fdf078bcb48bce4a2"),
        .init(fileName: "lm_r_xbx.marisa", md5: "d95157d1ff815b8d3e42b43660fdfa2f"),
        .init(fileName: "lm_u_abx.marisa", md5: "9d3d1be564f78e4f4ca2ec7629a2b80b"),
        .init(fileName: "lm_u_xbc.marisa", md5: "2c0f4652f78e8647cc70ab8eceba9b58")
    ]

    private static let zipURL = URL(string: "https://huggingface.co/Miwa-Keita/input_n5_lm_v1/resolve/main/input_n5_lm_v1.zip")!

    public static var requiredFileNames: [String] {
        Self.requiredFiles.map(\.fileName)
    }

    public static func modelDirectoryURL(azooKeyApplicationSupportDirectoryURL: URL) -> URL {
        azooKeyApplicationSupportDirectoryURL
            .appendingPathComponent("downloaded", isDirectory: true)
            .appendingPathComponent(Self.bundleDirectoryName, isDirectory: true)
    }

    public static func hasRequiredWeightFiles(modelDirectoryURL: URL) -> Bool {
        Self.requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: modelDirectoryURL.appendingPathComponent($0.fileName).path)
        }
    }

    public static func state(modelDirectoryURL: URL) -> DebugTypoCorrectionState {
        do {
            return try Self.validateWeights(modelDirectoryURL: modelDirectoryURL) ? .downloaded : .notDownloaded
        } catch {
            return .failed
        }
    }

    public static func validateWeights(modelDirectoryURL: URL) throws -> Bool {
        for required in Self.requiredFiles {
            let fileURL = modelDirectoryURL.appendingPathComponent(required.fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return false
            }
            let md5 = try Self.fileMD5HexString(fileURL: fileURL)
            guard md5 == required.md5 else {
                return false
            }
        }
        return true
    }

    public static func downloadWeights(modelDirectoryURL: URL) async throws {
        let fileManager = FileManager.default
        let parentDirectoryURL = modelDirectoryURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)

        let temporaryRootURL = fileManager.temporaryDirectory
            .appendingPathComponent("azookey-debug-tc-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryRootURL)
        }

        let downloadedZipTemporaryURL = temporaryRootURL.appendingPathComponent("input_n5_lm_v1.zip", isDirectory: false)
        let (temporaryFileURL, response) = try await URLSession.shared.download(from: Self.zipURL)
        if let httpResponse = response as? HTTPURLResponse, !(200 ... 299).contains(httpResponse.statusCode) {
            throw DebugTypoCorrectionWeightsError.invalidHTTPStatus(url: Self.zipURL, statusCode: httpResponse.statusCode)
        }
        try fileManager.moveItem(at: temporaryFileURL, to: downloadedZipTemporaryURL)

        let extractionRootURL = temporaryRootURL.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.unzipItem(at: downloadedZipTemporaryURL, to: extractionRootURL)

        let stagingDirectoryURL = extractionRootURL.appendingPathComponent(Self.bundleDirectoryName, isDirectory: true)
        guard fileManager.fileExists(atPath: stagingDirectoryURL.path) else {
            throw DebugTypoCorrectionWeightsError.extractedFolderNotFound(path: stagingDirectoryURL.path)
        }

        for required in Self.requiredFiles {
            let fileURL = stagingDirectoryURL.appendingPathComponent(required.fileName, isDirectory: false)
            let actualMD5 = try Self.fileMD5HexString(fileURL: fileURL)
            guard actualMD5 == required.md5 else {
                throw DebugTypoCorrectionWeightsError.hashMismatch(fileName: required.fileName, expected: required.md5, actual: actualMD5)
            }
        }

        if fileManager.fileExists(atPath: modelDirectoryURL.path) {
            try fileManager.removeItem(at: modelDirectoryURL)
        }
        try fileManager.moveItem(at: stagingDirectoryURL, to: modelDirectoryURL)
    }

    private static func fileMD5HexString(fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var md5 = Insecure.MD5()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty {
                break
            }
            md5.update(data: data)
        }
        return md5.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
