import Core
import KanaKanjiConverterModuleWithDefaultDictionary
import XCTest

@testable import azooKeyMac

@MainActor
final class PredictionCandidateNavigationTests: XCTestCase {
    private let shortcuts: [(Config.PredictionCandidateSelectionKeys.Value, KeyEventCore.ModifierFlag)] = [
        (.arrows, []), (.shift, .shift), (.command, .command), (.option, .option)
    ]

    private func presentations(_ texts: [String]) -> [CandidatePresentation] {
        texts.map { text in
            CandidatePresentation(candidate: Candidate(text: text, value: 0, composingCount: .surfaceCount(0), lastMid: 0, data: []))
        }
    }

    private func event(_ keyCode: UInt16, modifiers: KeyEventCore.ModifierFlag) -> KeyEventCore {
        KeyEventCore(modifierFlags: modifiers, characters: nil, charactersIgnoringModifiers: nil, keyCode: keyCode)
    }

    func testSelectedShortcutNavigatesAllPredictionsAndKeepsTheSelectionOnRefresh() {
        for (selectionKeys, modifiers) in self.shortcuts {
            let controller = PredictionCandidatesViewController()
            _ = controller.view
            let candidates = self.presentations(["おはよう", "おはようございます", "おはようございました"])
            controller.updateCandidatePresentations(candidates, selectionIndex: nil, cursorLocation: .zero)
            XCTAssertEqual(controller.numberOfVisibleRows, 3)
            XCTAssertEqual(controller.getSelectedCandidate()?.text, "おはよう")

            XCTAssertTrue(controller.handleNavigation(self.event(125, modifiers: modifiers), selectionKeys: selectionKeys))
            XCTAssertEqual(controller.getSelectedCandidate()?.text, "おはようございます")
            controller.updateCandidatePresentations(candidates, selectionIndex: nil, cursorLocation: .zero)
            XCTAssertEqual(controller.getSelectedCandidate()?.text, "おはようございます")
            XCTAssertTrue(controller.handleNavigation(self.event(125, modifiers: modifiers), selectionKeys: selectionKeys))
            XCTAssertEqual(controller.getSelectedCandidate()?.text, "おはようございました")
            XCTAssertTrue(controller.handleNavigation(self.event(126, modifiers: modifiers), selectionKeys: selectionKeys))
            XCTAssertEqual(controller.getSelectedCandidate()?.text, "おはようございます")
        }
    }

    func testOtherKeysAndModifiersRemainAvailableToTheirExistingHandlers() {
        for (selectionKeys, modifiers) in self.shortcuts {
            let controller = PredictionCandidatesViewController()
            _ = controller.view
            controller.updateCandidatePresentations(self.presentations(["候補1", "候補2"]), selectionIndex: nil, cursorLocation: .zero)
            for keyCode: UInt16 in [48, 36, 123, 124] {
                XCTAssertFalse(controller.handleNavigation(self.event(keyCode, modifiers: modifiers), selectionKeys: selectionKeys))
            }
            let otherModifiers: [KeyEventCore.ModifierFlag] = [[], .shift, .control, .option, .command, [.shift, .command]]
            for other in otherModifiers where other != modifiers {
                XCTAssertFalse(controller.handleNavigation(self.event(125, modifiers: other), selectionKeys: selectionKeys))
                XCTAssertFalse(controller.handleNavigation(self.event(126, modifiers: other), selectionKeys: selectionKeys))
            }
            XCTAssertEqual(controller.getSelectedCandidate()?.text, "候補1")
        }
    }

    func testSelectionResetsWhenTheCandidateDisappearsOrTheListCloses() {
        let controller = PredictionCandidatesViewController()
        _ = controller.view
        let candidates = self.presentations(["候補1", "候補2", "候補3"])
        controller.updateCandidatePresentations(candidates, selectionIndex: nil, cursorLocation: .zero)
        XCTAssertTrue(controller.handleNavigation(self.event(125, modifiers: .shift), selectionKeys: .shift))
        controller.updateCandidatePresentations(self.presentations(["候補3", "候補2"]), selectionIndex: nil, cursorLocation: .zero)
        XCTAssertEqual(controller.getSelectedCandidate()?.text, "候補2")
        controller.updateCandidatePresentations(self.presentations(["別候補"]), selectionIndex: nil, cursorLocation: .zero)
        XCTAssertEqual(controller.getSelectedCandidate()?.text, "別候補")
        controller.updateCandidatePresentations([], selectionIndex: nil, cursorLocation: .zero)
        XCTAssertNil(controller.getSelectedCandidate())
        XCTAssertFalse(controller.handleNavigation(self.event(125, modifiers: .shift), selectionKeys: .shift))
        controller.updateCandidatePresentations(candidates, selectionIndex: nil, cursorLocation: .zero)
        XCTAssertEqual(controller.getSelectedCandidate()?.text, "候補1")
    }
}
