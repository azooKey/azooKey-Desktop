/// Chromium IME deadlock workaround に関する回帰テスト。
///
/// Chrome 等の Chromium 系ブラウザで大規模 JS バンドルのページを開いた直後、
/// azooKey の activateServer 内で `client.attributes(forCharacterIndex:)` を呼ぶと
/// deadlock が発生する問題（Chromium issue 503787240）を回避するための変更を保護する。
///
/// 安全性の根拠：
/// - activateServer が渡す候補配列は空であるため、BaseCandidateViewController の
///   `resizeWindowToFitContent` は `numberOfVisibleRows == 0` で早期 return し、
///   cursorLocation は window 位置計算に使われない。
/// - この事実が変わらない限り、activateServer 時の client 問い合わせを削除しても
///   機能に影響がない。

import XCTest
import Core
import KanaKanjiConverterModuleWithDefaultDictionary
@testable import azooKeyMac

@MainActor
final class ChromiumDeadlockRegressionTests: XCTestCase {
    /// 空の候補配列で updateCandidatePresentations を呼んだ後、
    /// numberOfVisibleRows が 0 であることを確認する。
    ///
    /// これにより、resizeWindowToFitContent の `numberOfVisibleRows == 0` での
    /// 早期 return が継続的に機能することを保護する。
    func test空配列でupdateCandidatePresentationsを呼ぶとnumberOfVisibleRowsが0になる() {
        let vc = CandidatesViewController()
        _ = vc.view // loadView を強制実行
        vc.updateCandidatePresentations([], selectionIndex: nil, cursorLocation: .zero)
        XCTAssertEqual(
            vc.numberOfVisibleRows,
            0,
            "空の候補配列では numberOfVisibleRows は 0 でなければならない"
        )
    }

    /// 空の候補配列で updateCandidatePresentations を呼んだ後、
    /// candidates プロパティが空であることを確認する。
    func test空配列でupdateCandidatePresentationsを呼ぶとcandidatesが空になる() {
        let vc = CandidatesViewController()
        _ = vc.view
        vc.updateCandidatePresentations([], selectionIndex: nil, cursorLocation: .zero)
        XCTAssertTrue(vc.candidates.isEmpty, "空の候補配列を渡した後、candidates は空でなければならない")
    }

    /// 0 より多い候補配列を渡した後に空配列で更新すると、
    /// numberOfVisibleRows が 0 に戻ることを確認する。
    func test候補が存在する状態から空配列に更新するとnumberOfVisibleRowsが0になる() {
        let vc = CandidatesViewController()
        _ = vc.view
        let dummy = CandidatePresentation(
            candidate: Candidate(
                text: "テスト",
                value: 0,
                composingCount: .surfaceCount(3),
                lastMid: 0,
                data: []
            )
        )
        vc.updateCandidatePresentations([dummy], selectionIndex: nil, cursorLocation: .zero)
        XCTAssertEqual(vc.numberOfVisibleRows, 1, "候補が1件の状態を前提とする")

        vc.updateCandidatePresentations([], selectionIndex: nil, cursorLocation: .zero)
        XCTAssertEqual(
            vc.numberOfVisibleRows,
            0,
            "空配列に更新した後は numberOfVisibleRows が 0 でなければならない"
        )
    }
}
