#if os(macOS)
import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

private let zenzaiChoiceModelDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // InputUtilsTests
    .deletingLastPathComponent() // CoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // Core
    .deletingLastPathComponent()
    .appendingPathComponent("azooKeyMac/Resources/gguf")

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: zenzaiChoiceModelDirectory.appendingPathComponent("ggml-model-Q5_K_M.gguf").path
)))
func learnsFromSelectingAPrefixCandidateInFullConversion() throws {
    let config = Config.userDefaults
    let savedArguments = config.volatileDomain(forName: UserDefaults.argumentDomain)
    var arguments = savedArguments
    arguments[Config.Learning.key] = try JSONEncoder().encode(Config.Learning.Value.inputAndOutput)
    config.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    defer { config.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain) }

    let memory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: memory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: memory) }
    let manager = SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: memory,
        containerURL: nil,
        context: .init(useZenzai: true, resourcesDirectoryURL: zenzaiChoiceModelDirectory)
    )

    func currentCandidates() throws -> [Candidate] {
        guard case .selecting(let candidates, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
            throw CocoaError(.coderValueNotFound)
        }
        return candidates
    }

    for _ in 0..<12 {
        manager.insertAtCursorPosition("あらいさん", inputStyle: .direct)
        manager.update(requestRichCandidates: true)
        let candidates = try currentCandidates()
        if candidates.first?.text == "荒居さん" { break }
        let row = try #require(candidates.firstIndex { $0.text == "荒居" })
        manager.requestSelectingRow(row)
        let selected = try #require(manager.selectedCandidate)
        manager.recordSelectedCandidateCorrection(selected)
        manager.prefixCandidateCommited(selected, leftSideContext: "")
        #expect(manager.commitMarkedText(inputState: .previewing) == "さん")
    }
    #expect(try currentCandidates().first?.text == "荒居さん")
    manager.stopComposition()
    let reading = "せんたくきでふくをあらいます"
    for kana in reading {
        manager.insertAtCursorPosition(String(kana), inputStyle: .direct)
    }
    manager.update(requestRichCandidates: true)
    let firstFullCandidate = try currentCandidates().first { $0.data.map(\.ruby).joined() == reading.toKatakana() }
    #expect(firstFullCandidate?.text == "洗濯機で服を洗います")
}
#endif
