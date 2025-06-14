import Cocoa
import KanaKanjiConverterModule

class NonClickableTableView: NSTableView {
    override func rightMouseDown(with event: NSEvent) {}
    override func mouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}

class CandidateTableCellView: NSTableCellView {
    let candidateTextField: NSTextField

    override init(frame frameRect: NSRect) {
        self.candidateTextField = NSTextField(labelWithString: "")
        self.candidateTextField.font = NSFont.systemFont(ofSize: 18)
        super.init(frame: frameRect)
        self.addSubview(self.candidateTextField)

        self.candidateTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.candidateTextField.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            self.candidateTextField.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            self.candidateTextField.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])

        // 基本設定
        self.candidateTextField.isEditable = false
        self.candidateTextField.isBordered = false
        self.candidateTextField.drawsBackground = false
        self.candidateTextField.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            candidateTextField.textColor = backgroundStyle == .emphasized ? .white : NSAppearance.currentDrawing().name == .aqua ? .init(white: 0.3, alpha: 1.0) : .textColor
        }
    }
}

class BaseCandidateViewController: NSViewController {
    internal var candidates: [Candidate] = []
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
        self.tableView.rowHeight = 28

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

        window.contentView?.layer?.cornerRadius = 10
        window.backgroundColor = .clear
        window.isOpaque = false
    }

    func updateCandidates(_ candidates: [Candidate], selectionIndex: Int?, cursorLocation: CGPoint) {
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

    func getNewWindowFrame(currentFrame: NSRect, screenRect: NSRect, cursorLocation: CGPoint, desiredSize: CGSize, cursorHeight: CGFloat = 16) -> NSRect {
        var newWindowFrame = currentFrame
        newWindowFrame.size = desiredSize

        // 画面のサイズを取得
        let cursorY = cursorLocation.y

        // カーソルの高さを考慮してウィンドウ位置を調整
        // ウィンドウをカーソルの下に表示
        if cursorY - desiredSize.height < screenRect.origin.y {
            newWindowFrame.origin = CGPoint(x: cursorLocation.x, y: cursorLocation.y + cursorHeight)
        } else {
            newWindowFrame.origin = CGPoint(x: cursorLocation.x, y: cursorLocation.y - desiredSize.height - cursorHeight)
        }

        // 右端でウィンドウが画面外に出る場合は左にシフト
        if newWindowFrame.maxX > screenRect.maxX {
            newWindowFrame.origin.x = screenRect.maxX - newWindowFrame.width
        }
        return newWindowFrame
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

        let maxWidth = self.getMaxTextWidth(candidates: self.candidates.lazy.map { $0.text })
        let windowWidth = self.getWindowWidth(maxContentWidth: maxWidth)

        let newWindowFrame = self.getNewWindowFrame(
            currentFrame: window.frame,
            screenRect: screen.visibleFrame,
            cursorLocation: cursorLocation,
            desiredSize: CGSize(width: windowWidth, height: tableViewHeight)
        )
        if newWindowFrame != window.frame {
            window.setFrame(newWindowFrame, display: true, animate: false)
        }
    }

    func getSelectedCandidate() -> Candidate? {
        guard currentSelectedRow >= 0 && currentSelectedRow < candidates.count else {
            return nil
        }
        return candidates[currentSelectedRow]
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
        cell.candidateTextField.stringValue = candidates[row].text
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
