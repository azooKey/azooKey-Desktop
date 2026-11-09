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
private func withZenzaiLearningManager(_ body: @MainActor (SegmentsManager) throws -> Void) throws {
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

    try body(manager)
}

@MainActor
private func selectionCandidates(_ manager: SegmentsManager) throws -> [Candidate] {
    guard case .selecting(let candidates, _) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
        throw CocoaError(.coderValueNotFound)
    }
    return candidates
}

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: zenzaiChoiceModelDirectory.appendingPathComponent("ggml-model-Q5_K_M.gguf").path
)))
func learnsFromSelectingAPrefixCandidateInFullConversion() throws {
    try withZenzaiLearningManager { manager in
        for _ in 0..<12 {
            manager.insertAtCursorPosition("あらいさん", inputStyle: .direct)
            manager.update(requestRichCandidates: true)
            let candidates = try selectionCandidates(manager)
            if candidates.first?.text == "荒居さん" { break }
            let row = try #require(candidates.firstIndex { $0.text == "荒居" })
            manager.requestSelectingRow(row)
            let selected = try #require(manager.selectedCandidate)
            manager.recordSelectedCandidateCorrection(selected)
            manager.prefixCandidateCommited(selected, leftSideContext: "", isUserInitiated: true)
            #expect(manager.commitMarkedText(inputState: .previewing, isUserInitiated: true) == "さん")
        }
        #expect(try selectionCandidates(manager).first?.text == "荒居さん")
        manager.stopComposition()
        let reading = "せんたくきでふくをあらいます"
        for kana in reading {
            manager.insertAtCursorPosition(String(kana), inputStyle: .direct)
        }
        manager.update(requestRichCandidates: true)
        let firstFullCandidate = try selectionCandidates(manager).first { $0.data.map(\.ruby).joined() == reading.toKatakana() }
        #expect(firstFullCandidate?.text == "洗濯機で服を洗います")
    }
}

@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: zenzaiChoiceModelDirectory.appendingPathComponent("ggml-model-Q5_K_M.gguf").path
)))
func learnsFromCommittingBothSidesOfADifferentWordBoundary() throws {
    try withZenzaiLearningManager { manager in
        let reading = "しじついじゅう"
        @MainActor
        func startConversion() throws -> [Candidate] {
            manager.insertAtCursorPosition(reading, inputStyle: .direct)
            manager.update(requestRichCandidates: true)
            return try selectionCandidates(manager)
        }
        func firstFullCandidate(_ candidates: [Candidate]) -> String? {
            candidates.first { $0.data.map(\.ruby).joined() == "シジツイジュウ" }?.text
        }
        @MainActor
        func submitParts(_ candidates: [Candidate], confirmRemainder: Bool) throws {
            let row = try #require(candidates.firstIndex { $0.text == "指示" })
            manager.requestSelectingRow(row)
            let selected = try #require(manager.selectedCandidate)
            manager.recordSelectedCandidateCorrection(selected)
            manager.prefixCandidateCommited(selected, leftSideContext: "", isUserInitiated: true)
            #expect(manager.commitMarkedText(inputState: .previewing, isUserInitiated: confirmRemainder) == "追従")
        }

        // OS による残りの自動確定を、選び直しの一票として扱わない。
        for _ in 0..<6 {
            let candidates = try startConversion()
            #expect(firstFullCandidate(candidates) == "史実移住")
            try submitParts(candidates, confirmRemainder: false)
        }

        var first: String?
        for _ in 0..<10 {
            let candidates = try startConversion()
            first = firstFullCandidate(candidates)
            if first == "指示追従" { break }
            try submitParts(candidates, confirmRemainder: true)
        }
        #expect(first == "指示追従")
    }
}
@MainActor
@Test(.enabled(if: FileManager.default.fileExists(
    atPath: zenzaiChoiceModelDirectory.appendingPathComponent("ggml-model-Q5_K_M.gguf").path
)))
func learnsAWholePhraseWhenBothPartsAreSelected() throws {
    try withZenzaiLearningManager { manager in
        let reading = "あらいひかく"
        @MainActor
        func select(_ text: String, from candidates: [Candidate], leftSideContext: String) throws {
            let row = try #require(candidates.firstIndex { $0.text == text })
            manager.requestSelectingRow(row)
            let selected = try #require(manager.selectedCandidate)
            manager.recordSelectedCandidateCorrection(selected)
            manager.prefixCandidateCommited(selected, leftSideContext: leftSideContext, isUserInitiated: true)
        }

        var first: String?
        for _ in 0..<8 {
            manager.insertAtCursorPosition(reading, inputStyle: .direct)
            manager.update(requestRichCandidates: true)
            let candidates = try selectionCandidates(manager)
            first = candidates.first { $0.data.map(\.ruby).joined() == reading.toKatakana() }?.text
            if first == "粗い比較" { break }
            try select("粗い", from: candidates, leftSideContext: "")
            try select("比較", from: selectionCandidates(manager), leftSideContext: "粗い")
            #expect(manager.isEmpty)
            manager.stopComposition()
        }
        #expect(first == "粗い比較")
        manager.stopComposition()
        manager.insertAtCursorPosition("あらいさん", inputStyle: .direct)
        manager.update(requestRichCandidates: true)
        #expect(try selectionCandidates(manager).first?.text != "粗いさん")
    }
}
#endif
