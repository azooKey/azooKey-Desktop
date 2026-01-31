import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// SegmentsManagerの予測候補選択状態管理のテスト
@Suite("SegmentsManager Prediction Selection Tests")
struct SegmentsManagerPredictionSelectionTests {

    // MARK: - 初期状態のテスト

    @Test("初期状態でselectedPredictionIndexはnil")
    func testInitialStateIsNil() async throws {
        let manager = makeSegmentsManager()
        #expect(manager.selectedPredictionIndex == nil)
    }

    // MARK: - 次の候補を選択するテスト

    @Test("requestSelectingNextPredictionで最初の候補を選択できる")
    func testSelectingNextFromNil() async throws {
        let manager = makeSegmentsManager()
        manager.requestSelectingNextPrediction(count: 5)
        #expect(manager.selectedPredictionIndex == 0)
    }

    @Test("requestSelectingNextPredictionを複数回呼ぶとインクリメントされる")
    func testSelectingNextMultipleTimes() async throws {
        let manager = makeSegmentsManager()
        manager.requestSelectingNextPrediction(count: 5)
        manager.requestSelectingNextPrediction(count: 5)
        manager.requestSelectingNextPrediction(count: 5)
        #expect(manager.selectedPredictionIndex == 2)
    }

    @Test("requestSelectingNextPredictionで候補数を超えない")
    func testSelectingNextDoesNotExceedCount() async throws {
        let manager = makeSegmentsManager()
        // 3件の候補がある場合
        for _ in 0..<10 {
            manager.requestSelectingNextPrediction(count: 3)
        }
        // 最大でもcount - 1 (= 2)にとどまる
        #expect(manager.selectedPredictionIndex == 2)
    }

    @Test("候補数が0の場合はnilのまま")
    func testSelectingNextWithZeroCandidates() async throws {
        let manager = makeSegmentsManager()
        manager.requestSelectingNextPrediction(count: 0)
        #expect(manager.selectedPredictionIndex == nil)
    }

    // MARK: - 前の候補を選択するテスト

    @Test("requestSelectingPrevPredictionで前の候補を選択できる")
    func testSelectingPrev() async throws {
        let manager = makeSegmentsManager()
        manager.requestSelectingNextPrediction(count: 5)
        manager.requestSelectingNextPrediction(count: 5)
        manager.requestSelectingPrevPrediction()
        #expect(manager.selectedPredictionIndex == 0)
    }

    @Test("requestSelectingPrevPredictionで0からnilに戻る")
    func testSelectingPrevFromZeroBecomesNil() async throws {
        let manager = makeSegmentsManager()
        manager.requestSelectingNextPrediction(count: 5)
        #expect(manager.selectedPredictionIndex == 0)
        manager.requestSelectingPrevPrediction()
        #expect(manager.selectedPredictionIndex == nil)
    }

    @Test("requestSelectingPrevPredictionでnilからはnilのまま")
    func testSelectingPrevFromNilStaysNil() async throws {
        let manager = makeSegmentsManager()
        manager.requestSelectingPrevPrediction()
        #expect(manager.selectedPredictionIndex == nil)
    }

    // MARK: - リセットのテスト

    @Test("resetPredictionSelectionで選択がnilにリセットされる")
    func testResetPredictionSelection() async throws {
        let manager = makeSegmentsManager()
        manager.requestSelectingNextPrediction(count: 5)
        manager.requestSelectingNextPrediction(count: 5)
        #expect(manager.selectedPredictionIndex == 1)
        manager.resetPredictionSelection()
        #expect(manager.selectedPredictionIndex == nil)
    }

    // MARK: - Helper

    private func makeSegmentsManager() -> SegmentsManager {
        // テスト用の最小限のSegmentsManagerを作成
        // Note: KanaKanjiConverterのモック化が難しいため、実際のインスタンスを使用
        // ただし、予測候補選択の状態管理はConverterに依存しないためテスト可能
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return SegmentsManager(
            kanaKanjiConverter: .withDefaultDictionary(),
            applicationDirectoryURL: tempDir,
            containerURL: nil
        )
    }
}
