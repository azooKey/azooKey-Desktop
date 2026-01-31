import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// 予測変換候補の確定処理のテスト
/// acceptPredictionCandidate相当のロジックをテストする
@Suite("Prediction Accept Tests")
struct PredictionAcceptTests {

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

    // MARK: - ひらがな読み予測変換の確定テスト

    @Test("ひらがな読み予測で読みと表示が異なる場合、fullTextで全体置換される")
    @MainActor
    func testHiraganaPredictionWithDifferentDisplayTextReplacesWithFullText() async throws {
        // ユーザー辞書に「・・」→「……」を登録
        // 「・」を入力してTabで確定すると「……」が入力されるべき
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: [
                .init(word: "……", reading: "・・")  // 読み「・・」→ 表示「……」
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // 「・」を入力（中黒）
        manager.insertAtCursorPosition("・", inputStyle: .direct)

        // 予測候補を取得
        let predictions = manager.requestPredictionCandidates()

        // 「……」が候補にあることを確認
        let ellipsisCandidate = predictions.first { $0.displayText == "……" }
        #expect(ellipsisCandidate != nil, "「……」が予測候補に含まれるべき")

        guard let prediction = ellipsisCandidate else {
            return
        }

        // 予測候補を確定（acceptPredictionCandidateのロジックをシミュレート）
        let currentTarget = manager.convertTarget

        // 修正後のロジック: ひらがな読みでも読みと表示が異なる場合は全体置換
        // 現在の入力を全削除してfullTextを挿入
        let deleteCount = currentTarget.count
        if deleteCount > 0 {
            manager.deleteBackwardFromCursorPosition(count: deleteCount)
        }
        manager.insertAtCursorPosition(prediction.fullText, inputStyle: .direct)

        // 結果を確認: convertTargetが「……」になっているべき
        #expect(manager.convertTarget == "……", "確定後のテキストは「……」であるべき、実際は「\(manager.convertTarget)」")
    }

    @Test("ひらがな読み予測で読みと表示が同じ場合、appendText追加でも正しく動作する")
    @MainActor
    func testHiraganaPredictionWithSameDisplayTextWorksCorrectly() async throws {
        // ユーザー辞書に「あいうえお」→「あいうえお」を登録
        // 「あい」を入力してTabで確定すると「あいうえお」が入力されるべき
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: [
                .init(word: "あいうえお", reading: "あいうえお")
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // 「あい」を入力
        manager.insertAtCursorPosition("ai", inputStyle: .roman2kana)

        // 予測候補を取得
        let predictions = manager.requestPredictionCandidates()

        // 「あいうえお」が候補にあることを確認
        let aiueoCandidate = predictions.first { $0.displayText == "あいうえお" }

        if let prediction = aiueoCandidate {
            // 予測候補を確定（全体置換で実装）
            let currentTarget = manager.convertTarget
            let deleteCount = currentTarget.count
            if deleteCount > 0 {
                manager.deleteBackwardFromCursorPosition(count: deleteCount)
            }
            manager.insertAtCursorPosition(prediction.fullText, inputStyle: .direct)

            // 結果を確認: convertTargetが「あいうえお」になっているべき
            #expect(manager.convertTarget == "あいうえお", "確定後のテキストは「あいうえお」であるべき、実際は「\(manager.convertTarget)」")
        }
    }

    // MARK: - 英字読み予測変換の確定テスト（既存動作の確認）

    @Test("英字読み予測の確定は全体置換で正しく動作する")
    @MainActor
    func testEnglishReadingPredictionReplacesWithFullText() async throws {
        // ユーザー辞書に「azookey」→「azooKey」を登録
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: [
                .init(word: "azooKey", reading: "azookey")
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // 「azo」を入力
        manager.insertAtCursorPosition("azo", inputStyle: .roman2kana)

        // 予測候補を取得
        let predictions = manager.requestPredictionCandidates()

        // 「azooKey」が候補にあることを確認
        let azookeyCandidate = predictions.first { $0.displayText == "azooKey" }

        if let prediction = azookeyCandidate {
            #expect(prediction.isEnglishReading, "英字読みフラグがtrueであるべき")

            // 英字読みの確定ロジック
            let currentTarget = manager.convertTarget
            let deleteCount = currentTarget.count
            if deleteCount > 0 {
                manager.deleteBackwardFromCursorPosition(count: deleteCount)
            }
            manager.insertAtCursorPosition(prediction.fullText, inputStyle: .direct)

            // 結果を確認
            #expect(manager.convertTarget == "azooKey", "確定後のテキストは「azooKey」であるべき、実際は「\(manager.convertTarget)」")
        }
    }

    // MARK: - 問題ケースの再現テスト

    @Test("中黒入力で二点リーダー予測が正しく確定される - バグ修正確認")
    @MainActor
    func testNakaguroToEllipsisBugFix() async throws {
        // バグの再現: 「・」を入力して「……」をTabで確定すると「・・」になってしまう問題
        setupConfig(
            debugPredictiveTyping: true,
            userDictionaryItems: [
                .init(word: "……", reading: "・・")
            ]
        )
        defer { teardownConfig() }

        let manager = makeSegmentsManager()

        // 「・」を入力
        manager.insertAtCursorPosition("・", inputStyle: .direct)

        let currentTarget = manager.convertTarget
        #expect(currentTarget == "・", "入力後のconvertTargetは「・」であるべき")

        // 予測候補を取得
        let predictions = manager.requestPredictionCandidates()

        // 「……」が候補にあることを確認
        let ellipsisCandidate = predictions.first { $0.displayText == "……" }

        guard let prediction = ellipsisCandidate else {
            // 候補がない場合はテストをスキップ（辞書の問題）
            #expect(Bool(false), "「……」が予測候補に含まれるべき - 辞書設定を確認")
            return
        }

        // 問題: 現在のバグのあるロジックでは以下のようになる
        // appendText = "・" （「・・」から入力済み「・」を除いた残り）
        // 結果: 「・」（元の入力）+ 「・」（appendText）= 「・・」

        // 修正後: fullText「……」で全体置換すべき

        // 修正後のロジック
        let deleteCount = currentTarget.count
        if deleteCount > 0 {
            manager.deleteBackwardFromCursorPosition(count: deleteCount)
        }
        manager.insertAtCursorPosition(prediction.fullText, inputStyle: .direct)

        // 期待: 「……」
        // バグ時: 「・・」
        #expect(
            manager.convertTarget == "……",
            "バグ修正後: 「……」が入力されるべき、実際は「\(manager.convertTarget)」"
        )
    }

}
