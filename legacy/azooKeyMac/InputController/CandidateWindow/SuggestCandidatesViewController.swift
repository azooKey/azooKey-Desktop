import Cocoa
import KanaKanjiConverterModule

@MainActor protocol ReplaceSuggestionsViewControllerDelegate: AnyObject {
    func replaceSuggestionSelectionChanged(_ row: Int)
    func replaceSuggestionSubmitted()
}

class ReplaceSuggestionsViewController: BaseCandidateViewController {
    weak var delegate: (any ReplaceSuggestionsViewControllerDelegate)?

    override internal func updateSelectionCallback(_ row: Int) {
        delegate?.replaceSuggestionSelectionChanged(row)
    }

    func submitSelectedCandidate() {
        delegate?.replaceSuggestionSubmitted()
    }

    // overrideキーワードを削除し、NSTableViewDelegateのメソッドとして実装
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        updateSelection(to: row)
        return true
    }

    override var numberOfVisibleRows: Int {
        self.tableView.numberOfRows
    }

    override func getWindowWidth(maxContentWidth: CGFloat) -> CGFloat {
        maxContentWidth + 40
    }
}
