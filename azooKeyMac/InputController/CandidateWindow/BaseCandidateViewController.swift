import Cocoa
import Core
import KanaKanjiConverterModule

class NonClickableTableView: NSTableView {
    override func rightMouseDown(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}

class CandidateTableCellView: NSTableCellView {
    let candidateTextField: NSTextField
    let candidateAnnotationTextField: NSTextField
    private lazy var candidateTextFieldLeadingConstraint: NSLayoutConstraint = {
        self.candidateTextField.leadingAnchor.constraint(equalTo: self.leadingAnchor)
    }()
    private lazy var candidateTextFieldTrailingToAnnotationConstraint: NSLayoutConstraint = {
        self.candidateTextField.trailingAnchor.constraint(lessThanOrEqualTo: self.candidateAnnotationTextField.leadingAnchor, constant: -8)
    }()
    private lazy var candidateTextFieldTrailingToContainerConstraint: NSLayoutConstraint = {
        let constraint = self.candidateTextField.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        return constraint
    }()
    private lazy var candidateAnnotationTextFieldLeadingConstraint: NSLayoutConstraint = {
        self.candidateAnnotationTextField.leadingAnchor.constraint(greaterThanOrEqualTo: self.candidateTextField.trailingAnchor, constant: 8)
    }()
    private lazy var candidateAnnotationTextFieldTrailingConstraint: NSLayoutConstraint = {
        self.candidateAnnotationTextField.trailingAnchor.constraint(equalTo: self.trailingAnchor)
    }()

    override init(frame frameRect: NSRect) {
        self.candidateTextField = NSTextField(labelWithString: "")
        self.candidateTextField.font = NSFont.systemFont(ofSize: 18)
        self.candidateAnnotationTextField = NSTextField(labelWithString: "")
        self.candidateAnnotationTextField.font = NSFont.systemFont(ofSize: 12)
        self.candidateAnnotationTextField.textColor = .systemGray
        self.candidateAnnotationTextField.alignment = .right
        super.init(frame: frameRect)
        self.addSubview(self.candidateTextField)
        self.addSubview(self.candidateAnnotationTextField)

        self.candidateTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.candidateTextFieldLeadingConstraint,
            self.candidateTextFieldTrailingToContainerConstraint,
            self.candidateTextField.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
        self.candidateTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.candidateTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        self.candidateAnnotationTextField.translatesAutoresizingMaskIntoConstraints = false
        self.candidateAnnotationTextField.setContentHuggingPriority(.required, for: .horizontal)
        self.candidateAnnotationTextField.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            self.candidateAnnotationTextField.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])

        // 基本設定
        self.candidateTextField.isEditable = false
        self.candidateTextField.isBordered = false
        self.candidateTextField.drawsBackground = false
        self.candidateTextField.backgroundColor = .clear

        self.candidateAnnotationTextField.isEditable = false
        self.candidateAnnotationTextField.isBordered = false
        self.candidateAnnotationTextField.drawsBackground = false
        self.candidateAnnotationTextField.backgroundColor = .clear

        self.showCandidateAnnotationTextField(false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            candidateTextField.textColor = backgroundStyle == .emphasized ? .white : NSAppearance.currentDrawing().name == .aqua ? .init(white: 0.3, alpha: 1.0) : .textColor
            candidateAnnotationTextField.textColor = .systemGray
        }
    }

    func showCandidateAnnotationTextField(_ show: Bool) {
        self.candidateTextFieldTrailingToContainerConstraint.isActive = !show
        self.candidateTextFieldTrailingToAnnotationConstraint.isActive = show
        self.candidateAnnotationTextFieldLeadingConstraint.isActive = show
        self.candidateAnnotationTextFieldTrailingConstraint.isActive = show
        self.candidateAnnotationTextField.isHidden = !show
    }
}

class BaseCandidateViewController: NSViewController {
    internal var candidates: [CandidatePresentation] = []
    internal var tableView: NSTableView!
    internal var currentSelectedRow: Int = -1

    override func loadView() {
        // 親ビュー（ZStackのような役割）
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        // Material View（背景）
        let materialView = NSVisualEffectView()
        materialView.blendingMode = .behindWindow
        materialView.material = .windowBackground
        materialView.state = .active
        materialView.translatesAutoresizingMaskIntoConstraints = false

        // Scroll View（前面）
        let scrollView = NSScrollView()
        self.tableView = NonClickableTableView()
        self.tableView.style = .plain
        scrollView.documentView = self.tableView
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // 重ね順に応じて subviews を構成（背面 → 前面）
        containerView.subviews = [materialView, scrollView]

        // 制約
        NSLayoutConstraint.activate([
            materialView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            materialView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            materialView.topAnchor.constraint(equalTo: containerView.topAnchor),
            materialView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        self.tableView.backgroundColor = .clear
        self.tableView.gridStyleMask = .solidHorizontalGridLineMask

        // テーブルビューの構成
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("CandidatesColumn"))
        self.tableView.headerView = nil
        self.tableView.addTableColumn(column)
        self.tableView.delegate = self
        self.tableView.dataSource = self
        self.tableView.selectionHighlightStyle = .regular
        self.tableView.rowHeight = 32

        self.view = containerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureWindowForRoundedCorners()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureWindowForRoundedCorners()
    }

    internal func configureWindowForRoundedCorners() {
        guard let window = self.view.window else {
            return
        }

        window.contentView?.wantsLayer = true
        window.contentView?.layer?.masksToBounds = true

        window.styleMask = [.borderless, .resizable]
        window.isMovable = true
        window.hasShadow = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        window.contentView?.layer?.cornerRadius = 16
        window.backgroundColor = .clear
        window.isOpaque = false
    }

    func updateCandidatePresentations(_ candidates: [CandidatePresentation], selectionIndex: Int?, cursorLocation: CGPoint) {
        self.candidates = candidates
        self.currentSelectedRow = selectionIndex ?? -1
        self.tableView.reloadData()
        self.resizeWindowToFitContent(cursorLocation: cursorLocation)
        self.updateSelection(to: selectionIndex ?? -1)
    }

    internal func updateSelection(to row: Int) {
        if row == -1 {
            return
        }
        self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        self.tableView.scrollRowToVisible(row)
        self.updateSelectionCallback(row)
        self.currentSelectedRow = row
        self.updateVisibleRows()
    }

    internal func updateSelectionCallback(_ row: Int) {}

    internal func updateVisibleRows() {
        let visibleRows = self.tableView.rows(in: self.tableView.visibleRect)
        for row in visibleRows.lowerBound..<visibleRows.upperBound {
            if let cellView = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? CandidateTableCellView {
                self.configureCellView(cellView, forRow: row)
            }
        }
    }

    func getMaxTextWidth(candidates: some Sequence<String>, font: NSFont = .systemFont(ofSize: 18)) -> CGFloat {
        candidates.reduce(0) { maxWidth, candidate in
            let attributedString = NSAttributedString(
                string: candidate,
                attributes: [.font: font]
            )
            return max(maxWidth, attributedString.size().width)
        }
    }

    var numberOfVisibleRows: Int {
        self.candidates.count
    }

    func getWindowWidth(maxContentWidth: CGFloat) -> CGFloat {
        maxContentWidth
    }

    func resizeWindowToFitContent(cursorLocation: CGPoint) {
        guard let window = self.view.window, let screen = window.screen else {
            return
        }

        if self.numberOfVisibleRows == 0 {
            return
        }

        let rowHeight = self.tableView.rowHeight
        let tableViewHeight = CGFloat(self.numberOfVisibleRows) * rowHeight

        let maxWidth = self.getMaxTextWidth(candidates: self.candidates.lazy.map { $0.candidate.text })
        let windowWidth = self.getWindowWidth(maxContentWidth: maxWidth)
        let newWindowFrame = WindowPositioning.frameNearCursor(
            currentFrame: .init(window.frame),
            screenRect: .init(screen.visibleFrame),
            cursorLocation: .init(cursorLocation),
            desiredSize: .init(width: windowWidth, height: tableViewHeight)
        ).cgRect
        if newWindowFrame != window.frame {
            window.setFrame(newWindowFrame, display: true, animate: false)
        }
    }

    func getSelectedCandidate() -> Candidate? {
        guard currentSelectedRow >= 0 && currentSelectedRow < candidates.count else {
            return nil
        }
        return candidates[currentSelectedRow].candidate
    }

    func selectNextCandidate() {
        guard !candidates.isEmpty else {
            return
        }
        let nextRow = (currentSelectedRow + 1) % candidates.count
        updateSelection(to: nextRow)
    }

    func selectPrevCandidate() {
        guard !candidates.isEmpty else {
            return
        }
        let prevRow = (currentSelectedRow - 1 + candidates.count) % candidates.count
        updateSelection(to: prevRow)
    }

    internal func configureCellView(_ cell: CandidateTableCellView, forRow row: Int) {
        cell.candidateTextField.stringValue = candidates[row].candidate.text
        cell.showCandidateAnnotationTextField(false)
        cell.candidateAnnotationTextField.stringValue = ""
    }
}

extension BaseCandidateViewController: NSTableViewDelegate, NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        candidates.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier("CandidateCell")
        var cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? CandidateTableCellView

        if cell == nil {
            cell = CandidateTableCellView()
            cell?.identifier = cellIdentifier
        }

        if let cell = cell {
            configureCellView(cell, forRow: row)
        }

        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("CandidateRowView")
        var rowView = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTableRowView

        if rowView == nil {
            rowView = NSTableRowView()
            rowView?.identifier = identifier
        }

        return rowView
    }
}
