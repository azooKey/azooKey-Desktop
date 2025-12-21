import Cocoa
import KanaKanjiConverterModule

@MainActor protocol ReplaceSuggestionsViewControllerDelegate: AnyObject {
    func replaceSuggestionSelectionChanged(_ row: Int)
    func replaceSuggestionSubmitted()
}

class ReplaceSuggestionsViewController: BaseCandidateViewController {
    weak var delegate: (any ReplaceSuggestionsViewControllerDelegate)?
    private var modelLabel: NSTextField?

    private var modelDisplayName: String {
        let backend = Config.AIBackendPreference().value
        switch backend {
        case .off:
            return "Off"
        case .foundationModels:
            return "Foundation Models"
        case .openAI:
            let modelName = Config.OpenAiModelName().value
            return modelName.isEmpty ? "OpenAI API" : modelName
        }
    }

    override func loadView() {
        super.loadView()

        // Add model name label at the bottom of the window
        let label = NSTextField(labelWithString: modelDisplayName)
        label.font = NSFont.systemFont(ofSize: 8)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        self.modelLabel = label

        self.view.addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -2)
        ])
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Update model label when view appears
        modelLabel?.stringValue = modelDisplayName
    }

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
