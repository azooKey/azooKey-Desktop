import Cocoa
import SwiftUI

// Custom TextField with key handling
struct CustomTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @FocusState.Binding var isFocused: Bool
    var onSubmit: () -> Void
    var onDownArrow: () -> Void
    var onUpArrow: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let textField = KeyHandlingTextField()
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.textFieldAction(_:))

        // Set up appearance
        textField.isBordered = false
        textField.backgroundColor = NSColor.clear
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 12)
        textField.textColor = NSColor.labelColor

        // Set up key handling
        textField.onDownArrow = onDownArrow
        textField.onUpArrow = onUpArrow
        textField.onSubmit = onSubmit

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.stringValue = text

        // Update callbacks in case they changed
        if let keyTextField = nsView as? KeyHandlingTextField {
            keyTextField.onDownArrow = onDownArrow
            keyTextField.onUpArrow = onUpArrow
            keyTextField.onSubmit = onSubmit
        }

        // Handle focus changes
        if isFocused && nsView.window?.firstResponder != nsView {
            nsView.window?.makeFirstResponder(nsView)
        } else if !isFocused && nsView.window?.firstResponder == nsView {
            nsView.window?.makeFirstResponder(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CustomTextField

        init(_ parent: CustomTextField) {
            self.parent = parent
        }

        @objc func textFieldAction(_ sender: NSTextField) {
            parent.onSubmit()
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
        }
    }
}

private final class KeyHandlingTextField: NSTextField {
    var onDownArrow: (() -> Void)?
    var onUpArrow: (() -> Void)?
    var onSubmit: (() -> Void)?

    override func awakeFromNib() {
        super.awakeFromNib()
        setupCell()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCell()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }

    private func setupCell() {
        // Set up cell properties
        if let cell = self.cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byTruncatingTail
        }
    }

    override func keyDown(with event: NSEvent) {
        // Handle special keys first
        switch event.keyCode {
        case 125: // Down arrow key
            onDownArrow?()
            return // Don't call super to prevent default behavior
        case 126: // Up arrow key
            onUpArrow?()
            return // Don't call super to prevent default behavior
        case 36: // Return key
            onSubmit?()
            return
        default:
            super.keyDown(with: event)
        }
    }

    // Override interpretKeyEvents to prevent arrow key processing by the field editor
    override func interpretKeyEvents(_ eventArray: [NSEvent]) {
        for event in eventArray {
            switch event.keyCode {
            case 125, 126: // Up and down arrow keys
                // Skip interpretation for arrow keys - we handle them directly
                continue
            default:
                break
            }
        }
        super.interpretKeyEvents(eventArray.filter { ![125, 126].contains($0.keyCode) })
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Backup method to catch arrow keys
        if event.keyCode == 125 { // Down arrow key
            onDownArrow?()
            return true
        } else if event.keyCode == 126 { // Up arrow key
            onUpArrow?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // Override to intercept key events before they reach the field editor
    override func textShouldBeginEditing(_ textObject: NSText) -> Bool {
        true
    }
}
