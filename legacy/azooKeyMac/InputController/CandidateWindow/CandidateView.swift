import Cocoa
import Core
import KanaKanjiConverterModule

protocol CandidatesViewControllerDelegate: AnyObject {
    func candidateSubmitted()
    func candidateSelectionChanged(_ row: Int)
}

class CandidatesViewController: BaseCandidateViewController {
    weak var delegate: (any CandidatesViewControllerDelegate)?
    private var showedRows: ClosedRange = 0...8
    var showCandidateIndex = false

    override func updateCandidatePresentations(_ candidates: [CandidatePresentation], selectionIndex: Int?, cursorLocation: CGPoint) {
        self.showedRows = selectionIndex == nil ? 0...8 : self.showedRows
        super.updateCandidatePresentations(
            candidates,
            selectionIndex: selectionIndex,
            cursorLocation: cursorLocation
        )
    }

    override internal func updateSelectionCallback(_ row: Int) {
        delegate?.candidateSelectionChanged(row)

        if !self.showedRows.contains(row) {
            if row < self.showedRows.lowerBound {
                self.showedRows = row...(row + 8)
            } else {
                self.showedRows = (row - 8)...row
            }
        }
    }

    override internal func configureCellView(_ cell: CandidateTableCellView, forRow row: Int) {
        let candidate = self.candidates[row].candidate
        let annotationText = self.candidates[row].displayContext.annotationText
        let isWithinShowedRows = self.showedRows.contains(row)
        let displayIndex = row - self.showedRows.lowerBound + 1 // showedRowsの下限からの相対的な位置
        let displayText: String

        if isWithinShowedRows && self.showCandidateIndex {
            if displayIndex > 9 {
                displayText = " " + candidate.text // 行番号が10以上の場合、インデントを調整
            } else {
                displayText = "\(displayIndex). " + candidate.text
            }
        } else {
            displayText = candidate.text // showedRowsの範囲外では番号を付けない
        }

        // 数字部分と候補部分を別々に設定
        let attributedString = NSMutableAttributedString(string: displayText)
        let numberRange = (displayText as NSString).range(of: "\(displayIndex).")

        if numberRange.location != NSNotFound {
            attributedString.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
                .foregroundColor: currentSelectedRow == row ? NSColor.white : NSColor.gray,
                .baselineOffset: 2
            ], range: numberRange)
        }

        cell.candidateTextField.attributedStringValue = attributedString

        if let annotationText {
            let annotationString = NSAttributedString(
                string: annotationText,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 12),
                    .foregroundColor: currentSelectedRow == row ? NSColor.white : NSColor.systemGray
                ]
            )
            cell.showCandidateAnnotationTextField(true)
            cell.candidateAnnotationTextField.attributedStringValue = annotationString
        } else {
            cell.showCandidateAnnotationTextField(false)
            cell.candidateAnnotationTextField.stringValue = ""
        }
    }

    func getNumberCandidate(num: Int) -> Int {
        let nextRow = self.showedRows.lowerBound + num - 1
        return nextRow
    }

    func hide() {
        self.currentSelectedRow = -1
        self.showedRows = 0...8
    }

    override var numberOfVisibleRows: Int {
        min(9, self.tableView.numberOfRows)
    }

    override func getWindowWidth(maxContentWidth: CGFloat) -> CGFloat {
        let hasAnnotation = self.candidates.contains { $0.displayContext.annotationText != nil }
        if self.showCandidateIndex {
            return maxContentWidth + 48 + (hasAnnotation ? 56 : 0)
        } else {
            return maxContentWidth + 20 + (hasAnnotation ? 56 : 0)
        }
    }
}

class PredictionCandidatesViewController: BaseCandidateViewController {
    private let prefixTabStop: CGFloat = 24
    private let prefixSymbolName = "arrow.forward.to.line.compact"
    private let prefixFontSize: CGFloat = 12

    override var numberOfVisibleRows: Int {
        min(3, self.tableView.numberOfRows)
    }

    override internal func configureCellView(_ cell: CandidateTableCellView, forRow row: Int) {
        let candidateText = candidates[row].candidate.text
        let attributedString = NSMutableAttributedString()

        let isSelected = currentSelectedRow == row
        let candidateColor = isSelected ? NSColor.white : NSColor.labelColor

        if let symbol = NSImage(systemSymbolName: prefixSymbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: prefixFontSize, weight: .regular)
            let configured = symbol.withSymbolConfiguration(config) ?? symbol
            let attachment = NSTextAttachment()
            attachment.image = configured
            attachment.bounds = NSRect(x: 0, y: -2, width: prefixFontSize + 2, height: prefixFontSize + 2)
            attributedString.append(NSAttributedString(attachment: attachment))
        }
        attributedString.append(NSAttributedString(string: "\t"))
        let candidateAttributed = NSAttributedString(
            string: candidateText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18),
                .foregroundColor: candidateColor
            ]
        )
        attributedString.append(candidateAttributed)

        let fullRange = NSRange(location: 0, length: attributedString.length)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.tabStops = [
            NSTextTab(textAlignment: .left, location: prefixTabStop, options: [:])
        ]
        paragraphStyle.defaultTabInterval = prefixTabStop
        attributedString.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        cell.candidateTextField.attributedStringValue = attributedString
    }

    override func getWindowWidth(maxContentWidth: CGFloat) -> CGFloat {
        maxContentWidth + prefixTabStop + 20
    }
}
