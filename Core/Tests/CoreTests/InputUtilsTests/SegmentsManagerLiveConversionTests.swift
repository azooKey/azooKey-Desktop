import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// SegmentsManagerのライブ変換時のmarkedText表示テスト
@Suite("SegmentsManager Live Conversion MarkedText Tests")
struct SegmentsManagerLiveConversionTests {

    // MARK: - Setup / Teardown

    private func setupConfig(liveConversion: Bool = true) {
        UserDefaults.standard.set(
            liveConversion,
            forKey: Config.LiveConversion.key
        )
    }

    private func teardownConfig() {
        UserDefaults.standard.removeObject(forKey: Config.LiveConversion.key)
    }

    // MARK: - stale rawCandidates のテスト

    @Test("ライブ変換でstale候補の場合、新しく入力した文字が表示に含まれる")
    @MainActor
    func testStaleCandidatesShowNewlyTypedCharacter() async throws {
        setupConfig(liveConversion: true)
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // "かいぎ" を入力
        manager.insertAtCursorPosition("kaigi", inputStyle: .roman2kana)
        // rawCandidates を同期的に更新（"かいぎ" に対する変換結果を設定）
        manager.update(requestRichCandidates: false)

        // "の" を追加入力（rawCandidates は stale になる）
        manager.insertAtCursorPosition("no", inputStyle: .roman2kana)

        // rawCandidates が更新される前に getCurrentMarkedText を呼ぶ
        let markedText = manager.getCurrentMarkedText(inputState: .composing)
        let displayText = markedText.map(\.content).joined()

        // 新しく入力した "の" が表示に含まれるべき
        #expect(displayText.hasSuffix("の"), "stale候補でも新しく入力した文字が表示に含まれるべき。実際: \(displayText)")
        // convertTarget 全体（"かいぎの"）のひらがなだけにはならないことを確認
        // （ライブ変換の結果が使われている）
        #expect(displayText != manager.convertTarget || !displayText.hasSuffix("の"),
                "ライブ変換が有効なら変換結果が含まれるべき")
    }

    @Test("ライブ変換でstale候補の場合、表示テキストの長さがconvertTarget以上")
    @MainActor
    func testStaleCandidatesDisplayLengthMatchesInput() async throws {
        setupConfig(liveConversion: true)
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // "かいぎ" を入力して変換候補を確定
        manager.insertAtCursorPosition("kaigi", inputStyle: .roman2kana)
        manager.update(requestRichCandidates: false)

        let markedTextBefore = manager.getCurrentMarkedText(inputState: .composing)
        let displayBefore = markedTextBefore.map(\.content).joined()

        // "の" を追加（rawCandidates は stale）
        manager.insertAtCursorPosition("no", inputStyle: .roman2kana)

        let markedTextAfter = manager.getCurrentMarkedText(inputState: .composing)
        let displayAfter = markedTextAfter.map(\.content).joined()

        // 追加入力後の表示テキストは追加前より長いか同じ長さであるべき
        #expect(displayAfter.count >= displayBefore.count,
                "追加入力後の表示(\(displayAfter))は追加前(\(displayBefore))より短くなるべきではない")
    }

    // MARK: - fresh rawCandidates のテスト

    @Test("ライブ変換でfresh候補の場合、候補テキストがそのまま表示される")
    @MainActor
    func testFreshCandidatesShowConversionResult() async throws {
        setupConfig(liveConversion: true)
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // "かいぎ" を入力して変換候補を同期更新
        manager.insertAtCursorPosition("kaigi", inputStyle: .roman2kana)
        manager.update(requestRichCandidates: false)

        let markedText = manager.getCurrentMarkedText(inputState: .composing)
        let displayText = markedText.map(\.content).joined()

        // ライブ変換が有効で2文字以上の入力なら、変換結果が表示されるべき
        #expect(!displayText.isEmpty, "変換結果が表示されるべき")
        // convertTarget は "かいぎ" だが、ライブ変換により変換結果が表示される
        // 変換結果は辞書に依存するが、何かしらのテキストが返されるはず
    }

    // MARK: - rawCandidates が nil のテスト

    @Test("rawCandidatesがnilの場合、convertTargetが表示される")
    @MainActor
    func testNilCandidatesFallsBackToConvertTarget() async throws {
        setupConfig(liveConversion: true)
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // "かいぎ" を入力するが、update() を呼ばない（rawCandidates は nil のまま）
        // ただし deferredUpdateRawCandidate() が Task を予約するので、
        // Task が実行される前に getCurrentMarkedText を呼ぶ
        manager.insertAtCursorPosition("kaigi", inputStyle: .roman2kana)

        // rawCandidates が nil の場合は composingText.convertTarget がそのまま表示される
        let markedText = manager.getCurrentMarkedText(inputState: .composing)
        let displayText = markedText.map(\.content).joined()

        #expect(displayText == manager.convertTarget,
                "rawCandidatesがnilの場合、convertTarget(\(manager.convertTarget))が表示されるべき。実際: \(displayText)")
    }

    // MARK: - ライブ変換無効時のテスト

    @Test("ライブ変換無効時はconvertTargetが表示される")
    @MainActor
    func testDisabledLiveConversionShowsConvertTarget() async throws {
        setupConfig(liveConversion: false)
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // "かいぎ" を入力して変換候補を更新
        manager.insertAtCursorPosition("kaigi", inputStyle: .roman2kana)
        manager.update(requestRichCandidates: false)

        let markedText = manager.getCurrentMarkedText(inputState: .composing)
        let displayText = markedText.map(\.content).joined()

        // ライブ変換が無効なら、常に convertTarget（ひらがな）が表示される
        #expect(displayText == manager.convertTarget,
                "ライブ変換無効時はconvertTarget(\(manager.convertTarget))が表示されるべき。実際: \(displayText)")
    }

    // MARK: - ローマ字子音→母音結合時のテスト

    @Test("ローマ字の子音→母音結合時に未変換ローマ字が表示されない")
    @MainActor
    func testConsonantVowelCompletionDoesNotShowRawRoman() async throws {
        setupConfig(liveConversion: true)
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // "kaig" まで入力して変換候補を同期更新 → "かいg" に対する候補
        manager.insertAtCursorPosition("kaig", inputStyle: .roman2kana)
        manager.update(requestRichCandidates: false)

        // "i" を追加して "かいぎ" に（rawCandidates は "かいg" 時点のまま stale）
        manager.insertAtCursorPosition("i", inputStyle: .roman2kana)

        // rawCandidates が更新される前に getCurrentMarkedText を呼ぶ
        let markedText = manager.getCurrentMarkedText(inputState: .composing)
        let displayText = markedText.map(\.content).joined()

        // 表示テキストに未変換のローマ字 "g" が含まれてはいけない
        #expect(!displayText.contains("g"),
                "子音→母音結合後、未変換ローマ字が表示に含まれるべきではない。実際: \(displayText)")
    }

    // MARK: - Helper

    @MainActor
    private func makeSegmentsManager() -> SegmentsManager {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let manager = SegmentsManager(
            kanaKanjiConverter: .withDefaultDictionary(),
            applicationDirectoryURL: tempDir,
            containerURL: nil
        )
        manager.activate()
        return manager
    }
}
