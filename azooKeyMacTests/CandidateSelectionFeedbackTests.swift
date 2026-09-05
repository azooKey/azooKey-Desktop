import Core
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

    func testServerSnapshotSelectionDoesNotNotifySelectionDelegate() {
        let controller = CandidatesViewController()
        let delegate = DelegateSpy()
        controller.delegate = delegate
        _ = controller.view

        controller.updateCandidatePresentations(
            [
                ConverterCandidatePresentation(text: "候補1"),
                ConverterCandidatePresentation(text: "候補2")
            ],
            selectionIndex: 1,
            cursorLocation: .zero
        )

        XCTAssertEqual(controller.currentSelectedRow, 1)
        XCTAssertEqual(delegate.selectedRows, [], "Server状態の描画を新しい選択commandとして送り返してはいけない")
    }

    func testUserDrivenSelectionNotifiesSelectionDelegateOnce() {
        let controller = CandidatesViewController()
        let delegate = DelegateSpy()
        controller.delegate = delegate
        _ = controller.view
        controller.updateCandidatePresentations(
            [
                ConverterCandidatePresentation(text: "候補1"),
                ConverterCandidatePresentation(text: "候補2")
            ],
            selectionIndex: 0,
            cursorLocation: .zero
        )

        controller.selectNextCandidate()

        XCTAssertEqual(controller.currentSelectedRow, 1)
        XCTAssertEqual(delegate.selectedRows, [1])
    }

    func testSymbolAnnotationIsAccessibleAndClearedWhenCellIsReused() {
        let controller = CandidatesViewController()
        controller.candidates = [
            ConverterCandidatePresentation(text: "-", annotationText: "半角ハイフン"),
            ConverterCandidatePresentation(text: "文章")
        ]
        let cell = CandidateTableCellView()
        controller.configureCellView(cell, forRow: 0)
        XCTAssertFalse(cell.candidateAnnotationTextField.isHidden)
        XCTAssertEqual(cell.candidateTextField.accessibilityLabel(), "-、半角ハイフン")
        controller.configureCellView(cell, forRow: 1)
        XCTAssertTrue(cell.candidateAnnotationTextField.isHidden)
        XCTAssertEqual(cell.candidateTextField.accessibilityLabel(), "文章")
    }

    func testWindowWidthIncludesFullAnnotation() {
        let controller = CandidatesViewController()
        controller.candidates = [ConverterCandidatePresentation(text: "-", annotationText: "半角ハイフン")]
        let width = controller.getWindowWidth(maxContentWidth: 18)
        let annotationWidth = controller.getMaxTextWidth(candidates: ["半角ハイフン"], font: .systemFont(ofSize: 12))
        XCTAssertGreaterThanOrEqual(width, 18 + 20 + 8 + annotationWidth)
    }

}
