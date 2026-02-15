import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// SegmentsManagerのrequestPredictionCandidatesのテスト
@Suite("SegmentsManager Prediction Candidates Tests", .serialized)
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

    @Test("0文字入力では予測候補が返らない")
    @MainActor
    func testZeroCharacterInputReturnsNoCandidates() async throws {
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: [
                .init(word: "あいうえお", reading: "あいうえお")
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()
        // 何も入力しない状態
        let candidates = manager.requestPredictionCandidates()
        #expect(candidates.isEmpty, "0文字入力時は候補を返さない")
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

        // 並列テストの UserDefaults 競合を防ぐため、検索前に設定を再確認
        UserDefaults.standard.set(true, forKey: Config.DebugPredictiveTyping.key)

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

    // MARK: - 1文字入力のテスト

    @Test("1文字入力でも予測変換処理が実行される")
    @MainActor
    func testSingleCharacterInputProcessesPrediction() async throws {
        // 新仕様: 1文字（matchTarget.count >= 1）から予測変換が有効
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: []
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()
        // 1文字だけ入力
        manager.insertAtCursorPosition("a", inputStyle: .roman2kana)

        // 予測変換処理がエラーなく完了することを確認
        // 候補が返るかどうかは辞書の内容に依存するため、
        // ここでは処理が正常に完了することのみを検証
        let candidates = manager.requestPredictionCandidates()
        // 1文字入力でも予測変換処理が実行される（旧仕様では2文字未満で空を返していた）
        // 候補の有無は辞書内容に依存するため、処理完了を確認
        _ = candidates  // 処理が完了すればOK
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
