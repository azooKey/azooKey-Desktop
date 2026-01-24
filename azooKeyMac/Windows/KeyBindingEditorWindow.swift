import AppKit
import Carbon.HIToolbox
import Core
import SwiftUI

struct KeyBindingEditorWindow: View {
    typealias KeyBinding = Config.KeyBindings.KeyBinding
    typealias KeyBindingAction = Config.KeyBindings.KeyBindingAction
    typealias Modifier = Config.KeyBindings.Modifier

    init(bindings: [KeyBinding], onSave: @escaping (([KeyBinding]) -> Void)) {
        self.initialBindings = bindings
        self.onSave = onSave
        self._bindings = .init(initialValue: bindings)
    }

    private let initialBindings: [KeyBinding]
    private let onSave: (([KeyBinding]) -> Void)

    @State private var bindings: [KeyBinding] = []
    @State private var recordingAction: KeyBindingAction?
    @Environment(\.dismiss) private var dismiss

    private static let allActions: [KeyBindingAction] = [
        .backspace,
        .enter,
        .navigationUp,
        .navigationDown,
        .navigationRight,
        .navigationLeft,
        .editSegmentLeft,
        .editSegmentRight,
        .functionSix,
        .functionSeven,
        .functionEight,
        .functionNine,
        .functionTen,
        .suggest,
        .startUnicodeInput
    ]

    private func binding(for action: KeyBindingAction) -> KeyBinding? {
        bindings.first { $0.action == action }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            bindingListView
            Divider()
            footerView
        }
        .frame(width: 500, height: 480)
    }

    @ViewBuilder
    private var headerView: some View {
        VStack(spacing: 4) {
            Text("キーバインド")
                .font(.headline)
            if recordingAction != nil {
                Text("キーを入力してください（Escでキャンセル）")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var bindingListView: some View {
        List {
            ForEach(Self.allActions, id: \.self) { action in
                HStack {
                    Text(action.displayName)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    ShortcutButton(
                        binding: binding(for: action),
                        isRecording: recordingAction == action,
                        onStartRecording: {
                            recordingAction = action
                        },
                        onKeyRecorded: { key, modifiers in
                            setBinding(for: action, key: key, modifiers: modifiers)
                            recordingAction = nil
                        },
                        onCancelRecording: {
                            recordingAction = nil
                        }
                    )
                    .frame(width: 120)

                    Button {
                        clearBinding(for: action)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(binding(for: action) != nil ? .secondary : .clear)
                    }
                    .buttonStyle(.plain)
                    .disabled(binding(for: action) == nil)
                    .help("クリア")
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private var footerView: some View {
        HStack {
            Button("デフォルトに戻す") {
                resetToDefault()
            }

            Spacer()

            Button("キャンセル", role: .cancel) {
                dismiss()
            }

            Button("完了") {
                saveChanges()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func setBinding(for action: KeyBindingAction, key: String, modifiers: [Modifier]) {
        bindings.removeAll { $0.action == action }
        bindings.append(KeyBinding(key: key, modifiers: modifiers, action: action))
    }

    private func clearBinding(for action: KeyBindingAction) {
        bindings.removeAll { $0.action == action }
    }

    private func resetToDefault() {
        bindings = Config.KeyBindings.default.bindings
        recordingAction = nil
    }

    private func saveChanges() {
        onSave(bindings)
    }
}

struct ShortcutButton: View {
    let binding: Config.KeyBindings.KeyBinding?
    let isRecording: Bool
    let onStartRecording: () -> Void
    let onKeyRecorded: (String, [Config.KeyBindings.Modifier]) -> Void
    let onCancelRecording: () -> Void

    var body: some View {
        Group {
            if isRecording {
                KeyRecorderView(
                    onKeyRecorded: onKeyRecorded,
                    onCancel: onCancelRecording
                )
            } else {
                Button(action: onStartRecording) {
                    if let binding = binding {
                        ShortcutDisplayView(binding: binding)
                    } else {
                        Text("なし")
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct ShortcutDisplayView: View {
    let binding: Config.KeyBindings.KeyBinding

    var body: some View {
        HStack(spacing: 1) {
            ForEach(binding.modifiers.sorted(), id: \.self) { modifier in
                Text(modifier.symbol)
            }
            Text(binding.key.uppercased())
        }
        .font(.system(size: 13, design: .default))
        .foregroundColor(.primary)
    }
}

struct KeyRecorderView: NSViewRepresentable {
    let onKeyRecorded: (String, [Config.KeyBindings.Modifier]) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyRecorderNSView {
        let view = KeyRecorderNSView()
        view.onKeyRecorded = onKeyRecorded
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyRecorderNSView, context: Context) {
        nsView.onKeyRecorded = onKeyRecorded
        nsView.onCancel = onCancel
    }
}

class KeyRecorderNSView: NSView {
    var onKeyRecorded: ((String, [Config.KeyBindings.Modifier]) -> Void)?
    var onCancel: (() -> Void)?

    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "入力待ち...")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        return label
    }()

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
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.1).cgColor
        layer?.cornerRadius = 4

        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8)
        ])
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
            return
        }

        var modifiers: [Config.KeyBindings.Modifier] = []
        if event.modifierFlags.contains(.control) {
            modifiers.append(.control)
        }
        if event.modifierFlags.contains(.shift) {
            modifiers.append(.shift)
        }
        if event.modifierFlags.contains(.option) {
            modifiers.append(.option)
        }
        if event.modifierFlags.contains(.command) {
            modifiers.append(.command)
        }

        guard !modifiers.isEmpty else {
            return
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased(), !key.isEmpty else {
            return
        }

        let firstChar = key.first!
        guard firstChar.isLetter || firstChar.isNumber || firstChar.isPunctuation || firstChar.isSymbol else {
            return
        }

        onKeyRecorded?(key, modifiers)
    }

    override func flagsChanged(with event: NSEvent) {
        var parts: [String] = []
        if event.modifierFlags.contains(.control) {
            parts.append("⌃")
        }
        if event.modifierFlags.contains(.option) {
            parts.append("⌥")
        }
        if event.modifierFlags.contains(.shift) {
            parts.append("⇧")
        }
        if event.modifierFlags.contains(.command) {
            parts.append("⌘")
        }

        if parts.isEmpty {
            label.stringValue = "入力待ち..."
        } else {
            label.stringValue = parts.joined() + "..."
        }
    }
}

extension Config.KeyBindings.KeyBindingAction {
    var displayName: String {
        switch self {
        case .backspace: return "バックスペース"
        case .enter: return "確定（Enter）"
        case .navigationUp: return "上に移動"
        case .navigationDown: return "下に移動"
        case .navigationRight: return "右に移動"
        case .navigationLeft: return "左に移動"
        case .editSegmentLeft: return "文節を縮める"
        case .editSegmentRight: return "文節を伸ばす"
        case .functionSix: return "ひらがなに変換（F6）"
        case .functionSeven: return "カタカナに変換（F7）"
        case .functionEight: return "半角カタカナに変換（F8）"
        case .functionNine: return "全角英数に変換（F9）"
        case .functionTen: return "半角英数に変換（F10）"
        case .suggest: return "いい感じ変換"
        case .startUnicodeInput: return "Unicode入力開始"
        }
    }
}

extension Config.KeyBindings.Modifier: Comparable {
    public static func < (lhs: Config.KeyBindings.Modifier, rhs: Config.KeyBindings.Modifier) -> Bool {
        let order: [Config.KeyBindings.Modifier] = [.control, .option, .shift, .command]
        let lhsIndex = order.firstIndex(of: lhs) ?? 0
        let rhsIndex = order.firstIndex(of: rhs) ?? 0
        return lhsIndex < rhsIndex
    }

    var symbol: String {
        switch self {
        case .control: return "⌃"
        case .shift: return "⇧"
        case .option: return "⌥"
        case .command: return "⌘"
        }
    }
}

#Preview {
    KeyBindingEditorWindow(bindings: Config.KeyBindings.default.bindings) { _ in }
}
