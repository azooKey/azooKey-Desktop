import Core
import KanaKanjiConverterModuleWithDefaultDictionary
import XCTest

@testable import azooKeyMac

@MainActor
final class CandidateSelectionFeedbackTests: XCTestCase {
    private final class DelegateSpy: CandidatesViewControllerDelegate {
        var selectedRows: [Int] = []

        func candidateSubmitted() {}

        func candidateSelectionChanged(_ row: Int) {
            selectedRows.append(row)
        }
    }

    func testRenderingSelectionDoesNotNotifySelectionDelegate() {
        let controller = CandidatesViewController()
        let delegate = DelegateSpy()
        controller.delegate = delegate
        _ = controller.view

        controller.updateCandidatePresentations(
            [
                CandidatePresentation(candidate: Candidate(text: "候補1", value: 0, composingCount: .surfaceCount(0), lastMid: 0, data: [])),
                CandidatePresentation(candidate: Candidate(text: "候補2", value: 0, composingCount: .surfaceCount(0), lastMid: 0, data: []))
            ],
            selectionIndex: 1,
            cursorLocation: .zero
        )

        XCTAssertEqual(controller.currentSelectedRow, 1)
        XCTAssertEqual(delegate.selectedRows, [], "描画による選択更新をユーザー操作として通知してはいけない")
    }

    func testUserDrivenSelectionNotifiesSelectionDelegateOnce() {
        let controller = CandidatesViewController()
        let delegate = DelegateSpy()
        controller.delegate = delegate
        _ = controller.view
        controller.updateCandidatePresentations(
            [
                CandidatePresentation(candidate: Candidate(text: "候補1", value: 0, composingCount: .surfaceCount(0), lastMid: 0, data: [])),
                CandidatePresentation(candidate: Candidate(text: "候補2", value: 0, composingCount: .surfaceCount(0), lastMid: 0, data: []))
            ],
            selectionIndex: 0,
            cursorLocation: .zero
        )

        controller.selectNextCandidate()

        XCTAssertEqual(controller.currentSelectedRow, 1)
        XCTAssertEqual(delegate.selectedRows, [1])
    }
}
