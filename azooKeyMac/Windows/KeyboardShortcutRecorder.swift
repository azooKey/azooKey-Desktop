import AppKit
import SwiftUI

/// キーボードショートカットを記録するためのビュー
struct KeyboardShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcut
    var placeholder: String = "ショートカットを入力..."

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView()
        view.shortcut = shortcut
        view.placeholder = placeholder
        view.onShortcutChanged = { newShortcut in
            shortcut = newShortcut
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderView, context: Context) {
        if nsView.shortcut != shortcut {
            nsView.shortcut = shortcut
        }
    }
}

/// NSViewベースのショートカットレコーダー
class ShortcutRecorderView: NSView {
    var shortcut: KeyboardShortcut = .defaultTransformShortcut {
        didSet {
            needsDisplay = true
        }
    }
    var placeholder: String = "ショートカットを入力..."
    var onShortcutChanged: ((KeyboardShortcut) -> Void)?

    private var isRecording = false {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        // Escapeキーで録音をキャンセル
        if event.keyCode == 53 { // ESC
            window?.makeFirstResponder(nil)
            return
        }

        // Deleteキーでショートカットをクリア
        if event.keyCode == 51 || event.keyCode == 117 { // Delete or Forward Delete
            shortcut = .defaultTransformShortcut
            onShortcutChanged?(shortcut)
            window?.makeFirstResponder(nil)
            return
        }

        guard let characters = event.charactersIgnoringModifiers,
              !characters.isEmpty else {
            return
        }

        let key = characters.lowercased()
        let modifiers = EventModifierFlags(from: event.modifierFlags)

        // 修飾キーがない場合は無視
        guard modifiers.contains(.control) ||
                modifiers.contains(.option) ||
                modifiers.contains(.shift) ||
                modifiers.contains(.command) else {
            return
        }

        let newShortcut = KeyboardShortcut(key: key, modifiers: modifiers)
        shortcut = newShortcut
        onShortcutChanged?(newShortcut)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景
        let backgroundColor: NSColor = isRecording ? .controlAccentColor.withAlphaComponent(0.1) : .controlBackgroundColor
        backgroundColor.setFill()
        bounds.fill()

        // テキスト
        let text: String
        let textColor: NSColor

        if isRecording {
            text = "キーを入力..."
            textColor = .secondaryLabelColor
        } else {
            text = shortcut.displayString
            textColor = .labelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: textColor
        ]

        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )

        attributedString.draw(in: textRect)

        // フォーカスリング
        if isRecording {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set()
            bounds.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 120, height: 28)
    }
}
