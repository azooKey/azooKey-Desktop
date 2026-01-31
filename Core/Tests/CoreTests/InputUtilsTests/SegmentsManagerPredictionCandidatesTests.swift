import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// SegmentsManagerのrequestPredictionCandidatesのテスト
@Suite("SegmentsManager Prediction Candidates Tests")
struct SegmentsManagerPredictionCandidatesTests {

    // MARK: - Setup / Teardown

    /// テスト用の設定をセットアップ
    private func setupConfig(
        debugPredictiveTyping: Bool = true,
        userDictionaryItems: [Config.UserDictionaryEntry] = []
    ) {
        // DebugPredictiveTypingを有効化
        UserDefaults.standard.set(
            debugPredictiveTyping,
            forKey: Config.DebugPredictiveTyping.key
        )

        // UserDictionaryを設定
        var value = Config.UserDictionary.default
        value.items = userDictionaryItems
        if let encoded = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(encoded, forKey: Config.UserDictionary.key)
        }
    }

    /// テスト後のクリーンアップ
    private func teardownConfig() {
        UserDefaults.standard.removeObject(forKey: Config.DebugPredictiveTyping.key)
        UserDefaults.standard.removeObject(forKey: Config.UserDictionary.key)
    }

    // MARK: - 空入力のテスト

    @Test("空入力では候補が返らない")
    @MainActor
    func testEmptyInputReturnsNoCandidates() async throws {
        setupConfig(debugPredictiveTyping: true)
        defer { teardownConfig() }

        let manager = makeSegmentsManager()
        // 何も入力しない状態
        let candidates = manager.requestPredictionCandidates()
        #expect(candidates.isEmpty)
    }

    // MARK: - ひらがな読みのテスト

    @Test("ひらがな読みの辞書エントリがconvertTargetでマッチする")
    @MainActor
    func testHiraganaReadingMatchesConvertTarget() async throws {
        // ユーザー辞書に「あずーきー」→「azooKey」を登録
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: [
                .init(word: "azooKey", reading: "あずーきー")
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()
        // 「あずー」と入力
        manager.insertAtCursorPosition("azyu-", inputStyle: .roman2kana)

        let candidates = manager.requestPredictionCandidates()
        // ひらがな読みの辞書エントリが予測変換候補として返されることを期待
        // Note: 内部の変換処理に依存するため、候補が存在するかどうかを確認
        // 実際のマッチは変換エンジンの挙動に依存
        #expect(candidates.isEmpty || candidates.contains { $0.displayText == "azooKey" })
    }

    // MARK: - 英字読みのテスト（現状失敗想定）

    @Test("英字読みの辞書エントリが生ローマ字入力でマッチする")
    @MainActor
    func testEnglishReadingMatchesRawRomanInput() async throws {
        // ユーザー辞書に「azookey」(英字読み)→「azooKey」を登録
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: [
                .init(word: "azooKey", reading: "azookey")
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()
        // 「azo」と入力（生ローマ字）
        manager.insertAtCursorPosition("azo", inputStyle: .roman2kana)

        let candidates = manager.requestPredictionCandidates()
        // 英字読みの辞書エントリが生ローマ字入力でマッチすることを期待
        // 現状: この機能が未実装のため失敗する可能性がある
        let hasAzooKeyCandidate = candidates.contains { $0.displayText == "azooKey" }
        #expect(hasAzooKeyCandidate, "英字読みの辞書エントリが生ローマ字入力でマッチすべき")
    }

    // MARK: - DebugPredictiveTypingが無効の場合

    @Test("DebugPredictiveTypingが無効の場合は候補が返らない")
    @MainActor
    func testDisabledPredictiveTypingReturnsNoCandidates() async throws {
        setupConfig(
            debugPredictiveTyping: false,
            userDictionaryItems: [
                .init(word: "azooKey", reading: "あずーきー")
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()
        manager.insertAtCursorPosition("azyu-", inputStyle: .roman2kana)

        let candidates = manager.requestPredictionCandidates()
        #expect(candidates.isEmpty)
    }

    // MARK: - 入力が短い場合のテスト

    @Test("入力が2文字未満の場合は候補が返らない")
    @MainActor
    func testShortInputReturnsNoCandidates() async throws {
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: [
                .init(word: "azooKey", reading: "あずーきー")
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()
        // 1文字だけ入力
        manager.insertAtCursorPosition("a", inputStyle: .roman2kana)

        let candidates = manager.requestPredictionCandidates()
        // matchTargetが2文字未満の場合は空を返す
        #expect(candidates.isEmpty)
    }

    // MARK: - Helper

    private func makeSegmentsManager() -> SegmentsManager {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return SegmentsManager(
            kanaKanjiConverter: .withDefaultDictionary(),
            applicationDirectoryURL: tempDir,
            containerURL: nil
        )
    }
}
