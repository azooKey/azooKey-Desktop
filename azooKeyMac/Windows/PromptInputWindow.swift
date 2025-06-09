import Cocoa
import Foundation
import SwiftUI

extension Notification.Name {
    static let navigateHistoryUp = Notification.Name("navigateHistoryUp")
    static let navigateHistoryDown = Notification.Name("navigateHistoryDown")
    static let textFieldFocusChanged = Notification.Name("textFieldFocusChanged")
    static let requestTextFieldFocus = Notification.Name("requestTextFieldFocus")
}

class PromptInputWindow: NSWindow {
    private var completion: ((String?) -> Void)?
    private var previewCallback: ((String, @escaping (String) -> Void) -> Void)?
    private var applyCallback: ((String) -> Void)?
    private var isTextFieldCurrentlyFocused: Bool = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isReleasedWhenClosed = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.acceptsMouseMovedEvents = true

        // Use native material backing
        self.isOpaque = false
        self.alphaValue = 1.0

        setupUI()

        // Listen for text field focus changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textFieldFocusChanged(_:)),
            name: .textFieldFocusChanged,
            object: nil
        )
    }

    @objc private func textFieldFocusChanged(_ notification: Notification) {
        if let isFocused = notification.object as? Bool {
            isTextFieldCurrentlyFocused = isFocused
        }
    }

    private func setupUI() {
        let contentView = PromptInputView(
            onSubmit: { [weak self] prompt in
                self?.completion?(prompt)
                self?.close()
            },
            onPreview: { [weak self] prompt, callback in
                self?.previewCallback?(prompt, callback)
            },
            onApply: { [weak self] transformedText in
                self?.applyCallback?(transformedText)
            },
            onCancel: { [weak self] in
                self?.completion?(nil)
                self?.close()
            },
            onPreviewModeChanged: { [weak self] isPreviewMode in
                self?.resizeWindowToContent(isPreviewMode: isPreviewMode)
            }
        )

        self.contentView = NSHostingView(rootView: contentView)
    }

    func showPromptInput(
        at cursorLocation: NSPoint,
        onPreview: @escaping (String, @escaping (String) -> Void) -> Void,
        onApply: @escaping (String) -> Void,
        completion: @escaping (String?) -> Void
    ) {
        self.previewCallback = onPreview
        self.applyCallback = onApply
        self.completion = completion

        // Reset the window display state
        resetWindowState()

        // Initial resize to base size
        resizeWindowToContent(isPreviewMode: false)

        // Position window near cursor
        var windowFrame = self.frame
        windowFrame.origin = adjustWindowPosition(for: cursorLocation, windowSize: windowFrame.size)
        self.setFrame(windowFrame, display: true)

        self.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Set focus to text field with multiple attempts
        focusTextField()
    }

    private func resizeWindowToContent(isPreviewMode: Bool) {
        let headerHeight: CGFloat = 36  // Compact header
        let textFieldHeight: CGFloat = 36  // Compact text field
        let historyHeight: CGFloat = isPreviewMode ? 0 : 200  // More space for 10 items when not in preview mode
        let buttonHeight: CGFloat = 36  // Compact button row
        let containerPadding: CGFloat = 16  // Reduced padding

        let previewHeight: CGFloat = isPreviewMode ? 90 : 0  // Compact preview

        let totalHeight = headerHeight + textFieldHeight + historyHeight + buttonHeight + previewHeight + containerPadding

        var currentFrame = self.frame
        let newSize = NSSize(width: 360, height: totalHeight)

        // Adjust origin to keep the window in the same relative position
        currentFrame.origin.y += (currentFrame.size.height - newSize.height)
        currentFrame.size = newSize

        self.setFrame(currentFrame, display: true, animate: true)
    }

    private func resetWindowState() {
        // Reset the SwiftUI view state by creating a new content view
        setupUI()
    }

    private func focusTextField() {
        // Make window key and active
        NSApp.activate(ignoringOtherApps: true)
        self.makeKeyAndOrderFront(nil)

        // Single delayed focus request
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .requestTextFieldFocus, object: nil)
        }
    }

    private func adjustWindowPosition(for cursorLocation: NSPoint, windowSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursorLocation, $0.frame, false) }) ?? NSScreen.main else {
            return cursorLocation
        }

        let screenFrame = screen.visibleFrame
        var origin = cursorLocation

        // Offset slightly below and to the right of cursor
        origin.x += 10
        origin.y -= windowSize.height + 20

        // Ensure window stays within screen bounds with padding
        let padding: CGFloat = 20

        // Check right edge
        if origin.x + windowSize.width + padding > screenFrame.maxX {
            origin.x = screenFrame.maxX - windowSize.width - padding
        }

        // Check left edge
        if origin.x < screenFrame.minX + padding {
            origin.x = screenFrame.minX + padding
        }

        // Check bottom edge - if too low, show above cursor
        if origin.y < screenFrame.minY + padding {
            origin.y = cursorLocation.y + 30

            // If still doesn't fit above, position at screen edge
            if origin.y + windowSize.height + padding > screenFrame.maxY {
                origin.y = screenFrame.maxY - windowSize.height - padding
            }
        }

        // Check top edge
        if origin.y + windowSize.height + padding > screenFrame.maxY {
            origin.y = screenFrame.maxY - windowSize.height - padding
        }

        return origin
    }

    override func close() {
        // Call completion handler to reset flags before closing
        if let completion = self.completion {
            completion(nil)
        }

        // Restore focus to the previous application
        DispatchQueue.main.async {
            if let previousApp = NSWorkspace.shared.frontmostApplication {
                previousApp.activate(options: [])
            }
        }

        super.close()
        self.completion = nil
        self.previewCallback = nil
        self.applyCallback = nil
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        // Handle navigation keys at window level
        if event.keyCode == 53 { // Escape key
            // Send escape event to SwiftUI view and close window
            completion?(nil)
            close()
        } else if event.keyCode == 126 { // Up arrow key
            // Only handle up arrow if not in text field (CustomTextField handles it directly)
            if !isTextFieldCurrentlyFocused {
                NotificationCenter.default.post(name: .navigateHistoryUp, object: nil)
            } else {
                super.keyDown(with: event)
            }
        } else if event.keyCode == 125 { // Down arrow key
            // Only handle down arrow if not in text field (CustomTextField handles it directly)
            if !isTextFieldCurrentlyFocused {
                NotificationCenter.default.post(name: .navigateHistoryDown, object: nil)
            } else {
                super.keyDown(with: event)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

// Structure for prompt history item with pinned status
struct PromptHistoryItem: Codable {
    let prompt: String
    var isPinned: Bool = false
    var lastUsed: Date = Date()

    init(prompt: String, isPinned: Bool = false) {
        self.prompt = prompt
        self.isPinned = isPinned
        self.lastUsed = Date()
    }
}

struct PromptInputView: View {
    @State private var promptText: String = ""
    @State private var previewText: String = ""
    @State private var isLoading: Bool = false
    @State private var showPreview: Bool = false
    @State private var promptHistory: [PromptHistoryItem] = []
    @State private var hoveredHistoryIndex: Int?
    @FocusState private var isTextFieldFocused: Bool

    let onSubmit: (String?) -> Void
    let onPreview: (String, @escaping (String) -> Void) -> Void
    let onApply: (String) -> Void
    let onCancel: () -> Void
    let onPreviewModeChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 4) {
            // Header with Apple Intelligence-like design
            HStack {
                // Gradient AI icon with glow effect
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 16, height: 16)
                        .blur(radius: 2)
                        .opacity(0.7)

                    Image(systemName: "sparkles")
                        .foregroundColor(.white)
                        .font(.system(size: 8, weight: .semibold))
                }

                Text("AI Transform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .secondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .foregroundColor(.secondary.opacity(0.8))
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            // Input field with custom key handling
            CustomTextField(
                text: $promptText,
                placeholder: "例: フォーマルにして",
                isFocused: $isTextFieldFocused,
                onSubmit: {
                    if hoveredHistoryIndex != nil {
                        // If history item is selected, use it and generate preview automatically
                        promptText = getVisibleHistory()[hoveredHistoryIndex!].prompt
                        hoveredHistoryIndex = nil
                        isTextFieldFocused = true
                        // Automatically request preview after setting the text
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            requestPreview()
                        }
                    } else if showPreview {
                        // Apply when Enter is pressed in preview mode
                        onApply(previewText)
                        onSubmit(promptText)
                    } else {
                        // Preview when Enter is pressed in input mode
                        requestPreview()
                    }
                },
                onDownArrow: {
                    // Handle down arrow to start history navigation
                    navigateHistory(direction: .down)
                },
                onUpArrow: {
                    // Handle up arrow for history navigation
                    navigateHistory(direction: .up)
                }
            )
            .onChange(of: isTextFieldFocused) { isFocused in
                // Notify parent window about focus changes
                NotificationCenter.default.post(name: .textFieldFocusChanged, object: isFocused)
            }
            .onChange(of: promptText) { _ in
                // When text field is edited after preview, hide preview and show history
                if showPreview {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPreview = false
                        onPreviewModeChanged(false)
                    }
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            )

            // Recent prompts (visible when not in preview mode and available)
            if !promptHistory.isEmpty && !showPreview {
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text("Recent")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 1) {
                            ForEach(Array(getVisibleHistory().enumerated()), id: \.offset) { index, item in
                                HStack(spacing: 4) {
                                    // Pin button
                                    Button {
                                        togglePin(for: item)
                                    } label: {
                                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                                            .font(.system(size: 9))
                                            .foregroundColor(item.isPinned ? .accentColor : .secondary.opacity(0.4))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .help(item.isPinned ? "Unpin" : "Pin")

                                    // Prompt text
                                    Text(item.prompt)
                                        .font(.system(size: 11))
                                        .foregroundColor(hoveredHistoryIndex == index ? .primary : .secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(hoveredHistoryIndex == index ? Color.accentColor.opacity(0.2) : Color.clear)
                                )
                                .onHover { isHovered in
                                    hoveredHistoryIndex = isHovered ? index : nil
                                }
                                .onTapGesture {
                                    promptText = item.prompt
                                    hoveredHistoryIndex = nil
                                    isTextFieldFocused = true
                                    // Automatically request preview after setting the text
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        requestPreview()
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
            }

            // Preview section with enhanced design
            if showPreview {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Preview")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    ScrollView {
                        Text(previewText)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.thinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                    .frame(minHeight: 40, maxHeight: 70)
                }
                .padding(.horizontal, 12)
            }

            // Action buttons with modern styling
            HStack(spacing: 10) {
                if showPreview {
                    Button("Edit") {
                        showPreview = false
                        // Notify parent window about preview mode change
                        onPreviewModeChanged(false)
                        DispatchQueue.main.async {
                            isTextFieldFocused = true
                        }
                    }
                    .buttonStyle(ModernSecondaryButtonStyle())

                    Spacer()

                    Button("Apply") {
                        // Execute apply first
                        onApply(previewText)

                        // Close window and submit
                        onSubmit(promptText)
                    }
                    .buttonStyle(ModernPrimaryButtonStyle())
                } else {
                    Spacer()

                    Button(isLoading ? "Generating..." : "Preview") {
                        requestPreview()
                    }
                    .buttonStyle(ModernPrimaryButtonStyle())
                    .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.quaternary, lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .onAppear {
            // Reset all state variables when the view appears
            promptText = ""
            previewText = ""
            isLoading = false
            showPreview = false
            hoveredHistoryIndex = nil

            // Load prompt history
            loadPromptHistory()

            // Notify initial preview mode state
            onPreviewModeChanged(false)

            // Simple focus setting
            isTextFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateHistoryUp)) { _ in
            navigateHistory(direction: .up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateHistoryDown)) { _ in
            navigateHistory(direction: .down)
        }
        .onReceive(NotificationCenter.default.publisher(for: .requestTextFieldFocus)) { _ in
            // Force focus to text field
            isTextFieldFocused = true
        }
    }

    private func requestPreview() {
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        // Save prompt to history
        savePromptToHistory(trimmedPrompt)

        // Reset hover when requesting preview
        hoveredHistoryIndex = nil

        isLoading = true
        onPreview(trimmedPrompt) { result in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.previewText = result
                    self.isLoading = false
                    self.showPreview = true
                    // Notify parent window about preview mode change
                    self.onPreviewModeChanged(true)
                }
            }
        }
    }

    private func loadPromptHistory() {
        let historyString = UserDefaults.standard.string(forKey: "dev.ensan.inputmethod.azooKeyMac.preference.PromptHistory") ?? ""
        if !historyString.isEmpty,
           let data = historyString.data(using: .utf8) {
            // Try to load new format first
            if let history = try? JSONDecoder().decode([PromptHistoryItem].self, from: data) {
                promptHistory = history
            } else if let oldHistory = try? JSONDecoder().decode([String].self, from: data) {
                // Convert old format to new format
                promptHistory = oldHistory.map { PromptHistoryItem(prompt: $0, isPinned: false) }
                savePinnedHistory() // Save in new format
            }
        }
    }

    private func getVisibleHistory() -> [PromptHistoryItem] {
        let pinnedItems = promptHistory.filter { $0.isPinned }
        let recentItems = promptHistory.filter { !$0.isPinned }.prefix(10 - pinnedItems.count)
        return Array(pinnedItems + recentItems)
    }

    private func togglePin(for item: PromptHistoryItem) {
        if let index = promptHistory.firstIndex(where: { $0.prompt == item.prompt }) {
            promptHistory[index].isPinned.toggle()
            savePinnedHistory()
        }
    }

    private func savePromptToHistory(_ prompt: String) {
        // Remove if already exists to move to front
        promptHistory.removeAll { $0.prompt == prompt }

        // Add to front
        let newItem = PromptHistoryItem(prompt: prompt, isPinned: false)
        promptHistory.insert(newItem, at: 0)

        // Keep only last 10 prompts (excluding pinned)
        let pinnedItems = promptHistory.filter { $0.isPinned }
        let recentItems = promptHistory.filter { !$0.isPinned }.prefix(10)
        promptHistory = Array(pinnedItems + recentItems)

        // Save to UserDefaults
        savePinnedHistory()
    }

    private func savePinnedHistory() {
        if let data = try? JSONEncoder().encode(promptHistory) {
            UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: "dev.ensan.inputmethod.azooKeyMac.preference.PromptHistory")
        }
    }

    private enum NavigationDirection {
        case up, down
    }

    private func navigateHistory(direction: NavigationDirection) {
        let visibleHistory = getVisibleHistory()
        guard !visibleHistory.isEmpty else {
            return
        }

        let maxIndex = visibleHistory.count - 1

        switch direction {
        case .up:
            if hoveredHistoryIndex == nil {
                hoveredHistoryIndex = maxIndex
            } else if hoveredHistoryIndex! > 0 {
                hoveredHistoryIndex! -= 1
            } else {
                // When at the first history item and pressing up, return to text field
                hoveredHistoryIndex = nil
                isTextFieldFocused = true
                return // Don't update promptText, keep current text
            }
        case .down:
            if hoveredHistoryIndex == nil {
                // When down is pressed from text field, start history navigation
                hoveredHistoryIndex = 0
                isTextFieldFocused = false // Remove focus from text field
            } else if hoveredHistoryIndex! < maxIndex {
                hoveredHistoryIndex! += 1
            } else {
                // At the end of history, cycle back to start
                hoveredHistoryIndex = 0
            }
        }

        // Update text field with hovered history item
        if let index = hoveredHistoryIndex {
            promptText = visibleHistory[index].prompt
        }
    }
}

// Modern macOS-style button designs
struct ModernPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .brightness(configuration.isPressed ? -0.1 : 0)
                    .saturation(configuration.isPressed ? 0.8 : 1.0)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ModernSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.regularMaterial)
                    .opacity(configuration.isPressed ? 0.7 : 1.0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 0.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

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

class KeyHandlingTextField: NSTextField {
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

#Preview {
    PromptInputView(
        onSubmit: { prompt in
            print("Prompt: \(prompt ?? "nil")")
        },
        onPreview: { prompt, callback in
            print("Preview request: \(prompt)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                callback("Transformed: \(prompt)")
            }
        },
        onApply: { text in
            print("Apply: \(text)")
        },
        onCancel: {
            print("Cancel")
        },
        onPreviewModeChanged: { isPreviewMode in
            print("Preview mode changed: \(isPreviewMode)")
        }
    )
    .frame(width: 380)
}
