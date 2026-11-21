@testable import Core
import Foundation
import Testing

@Test func testTypoCorrectionRequiresReadableWeightFiles() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(!DebugTypoCorrectionWeights.canReadRequiredWeightFiles(modelDirectoryURL: directory))

    let fileURLs = DebugTypoCorrectionWeights.requiredFileNames.map { directory.appendingPathComponent($0) }
    for url in fileURLs {
        try Data([0]).write(to: url)
    }
    #expect(DebugTypoCorrectionWeights.canReadRequiredWeightFiles(modelDirectoryURL: directory))

    let firstFile = try #require(fileURLs.first)
    try Data().write(to: firstFile)
    #expect(!DebugTypoCorrectionWeights.canReadRequiredWeightFiles(modelDirectoryURL: directory))

    try FileManager.default.removeItem(at: firstFile)
    try FileManager.default.createDirectory(at: firstFile, withIntermediateDirectories: false)
    #expect(DebugTypoCorrectionWeights.hasRequiredWeightFiles(modelDirectoryURL: directory))
    #expect(!DebugTypoCorrectionWeights.canReadRequiredWeightFiles(modelDirectoryURL: directory))
}
