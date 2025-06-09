import Cocoa
import Foundation
import SwiftUI

extension Notification.Name {
    static let navigateHistoryUp = Notification.Name("navigateHistoryUp")
    static let navigateHistoryDown = Notification.Name("navigateHistoryDown")
    static let textFieldFocusChanged = Notification.Name("textFieldFocusChanged")
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
        // Enhanced focus handling with more aggressive approach
        NSApp.activate(ignoringOtherApps: true)
        self.orderFront(nil)
        self.makeKeyAndOrderFront(nil)

        // Force the window to become key immediately
        if !self.isKeyWindow {
            self.makeKey()
        }

        // Multiple attempts to ensure the text field gets focus with extended timing
        self.makeFirstResponder(self.contentView)

        // Extended focus attempts with more frequent retries
        for delay in [0.01, 0.02, 0.05, 0.1, 0.15, 0.2, 0.3, 0.4, 0.5, 0.7, 1.0, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !self.isKeyWindow {
                    NSApp.activate(ignoringOtherApps: true)
                    self.makeKeyAndOrderFront(nil)
                }
                self.makeFirstResponder(self.contentView)
            }
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
            // Send up arrow event to SwiftUI view for history navigation
            NotificationCenter.default.post(name: .navigateHistoryUp, object: nil)
        } else if event.keyCode == 125 { // Down arrow key
            if isTextFieldCurrentlyFocused {
                // When text field is focused and down key is pressed, start history navigation
                NotificationCenter.default.post(name: .navigateHistoryDown, object: nil)
            } else {
                // Continue with normal history navigation
                NotificationCenter.default.post(name: .navigateHistoryDown, object: nil)
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

            // Input field with keyboard navigation
            TextField("例: フォーマルにして", text: $promptText)
                .textFieldStyle(ModernTextFieldStyle())
                .focused($isTextFieldFocused)
                .onChange(of: isTextFieldFocused) { isFocused in
                    // Notify parent window about focus changes
                    NotificationCenter.default.post(name: .textFieldFocusChanged, object: isFocused)
                }
                .onSubmit {
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
                }
                .onTapGesture {
                    hoveredHistoryIndex = nil
                    isTextFieldFocused = true
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
            ZStack {
                // Glass blur effect
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .opacity(0.8)

                // Subtle gradient overlay
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.1),
                                Color.clear,
                                Color.black.opacity(0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // Border highlight
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.3),
                                Color.white.opacity(0.1),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 12)
            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
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

            // Enhanced focus handling with more aggressive timing
            isTextFieldFocused = true

            // Multiple attempts to ensure focus is properly set with extended timing
            for delay in [0.0, 0.01, 0.05, 0.1, 0.15, 0.2, 0.3, 0.5, 0.7, 1.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    isTextFieldFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateHistoryUp)) { _ in
            navigateHistory(direction: .up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateHistoryDown)) { _ in
            navigateHistory(direction: .down)
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
                hoveredHistoryIndex = 0
            } else if hoveredHistoryIndex! < maxIndex {
                hoveredHistoryIndex! += 1
            } else {
                hoveredHistoryIndex = nil
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

struct ModernTextFieldStyle: TextFieldStyle {
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            )
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
