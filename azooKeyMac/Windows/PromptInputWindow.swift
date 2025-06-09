import Cocoa
import SwiftUI

class PromptInputWindow: NSWindow {
    private var completion: ((String?) -> Void)?
    private var previewCallback: ((String, @escaping (String) -> Void) -> Void)?
    private var applyCallback: ((String) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isReleasedWhenClosed = false
        self.backgroundColor = NSColor.clear
        self.hasShadow = true
        self.acceptsMouseMovedEvents = true

        setupUI()
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
        let baseHeight: CGFloat = 120  // Base height for input field and buttons
        let previewHeight: CGFloat = isPreviewMode ? 100 : 0  // Additional height for preview
        let totalHeight = baseHeight + previewHeight

        var currentFrame = self.frame
        let newSize = NSSize(width: 380, height: totalHeight)

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
        // Force window to be key and active
        self.orderFront(nil)
        self.makeKeyAndOrderFront(nil)

        // Multiple attempts to ensure the text field gets focus
        self.makeFirstResponder(self.contentView)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.makeFirstResponder(self.contentView)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.makeFirstResponder(self.contentView)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.makeFirstResponder(self.contentView)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.makeFirstResponder(self.contentView)
        }
    }

    private func adjustWindowPosition(for cursorLocation: NSPoint, windowSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else {
            return cursorLocation
        }

        let screenFrame = screen.visibleFrame
        var origin = cursorLocation

        // Offset slightly below and to the right of cursor
        origin.x += 10
        origin.y -= windowSize.height + 20

        // Ensure window stays within screen bounds
        if origin.x + windowSize.width > screenFrame.maxX {
            origin.x = screenFrame.maxX - windowSize.width - 10
        }
        if origin.y < screenFrame.minY {
            origin.y = cursorLocation.y + 30
        }
        if origin.x < screenFrame.minX {
            origin.x = screenFrame.minX + 10
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
        // Handle Escape key at window level
        if event.keyCode == 53 { // Escape key
            completion?(nil)
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

struct PromptInputView: View {
    @State private var promptText: String = ""
    @State private var previewText: String = ""
    @State private var isLoading: Bool = false
    @State private var showPreview: Bool = false
    @FocusState private var isTextFieldFocused: Bool

    let onSubmit: (String?) -> Void
    let onPreview: (String, @escaping (String) -> Void) -> Void
    let onApply: (String) -> Void
    let onCancel: () -> Void
    let onPreviewModeChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundColor(.blue)
                    .font(.system(size: 14, weight: .medium))

                Text("AI Text Transform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.escape)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Input field
            TextField("例: フォーマルにして", text: $promptText)
                .textFieldStyle(ModernTextFieldStyle())
                .focused($isTextFieldFocused)
                .onSubmit {
                    if showPreview {
                        // Apply when Enter is pressed in preview mode
                        onApply(previewText)
                        onSubmit(promptText)
                    } else {
                        // Preview when Enter is pressed in input mode
                        requestPreview()
                    }
                }
                .onTapGesture {
                    isTextFieldFocused = true
                }
                .padding(.horizontal, 12)

            // Preview section
            if showPreview {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Preview:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    ScrollView {
                        Text(previewText)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.gray.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                                    )
                            )
                    }
                    .frame(minHeight: 40, maxHeight: 80)
                }
                .padding(.horizontal, 12)
            }

            // Action buttons
            HStack(spacing: 8) {
                if showPreview {
                    Button("Edit") {
                        showPreview = false
                        // Notify parent window about preview mode change
                        onPreviewModeChanged(false)
                        DispatchQueue.main.async {
                            isTextFieldFocused = true
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Spacer()

                    Button("Apply") {
                        // Execute apply first
                        onApply(previewText)

                        // Close window and submit
                        onSubmit(promptText)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Spacer()

                    Button(isLoading ? "Loading..." : "Preview") {
                        requestPreview()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        )
        .onAppear {
            // Reset all state variables when the view appears
            promptText = ""
            previewText = ""
            isLoading = false
            showPreview = false

            // Notify initial preview mode state
            onPreviewModeChanged(false)

            // Set focus to text field with aggressive timing
            DispatchQueue.main.async {
                isTextFieldFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isTextFieldFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isTextFieldFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isTextFieldFocused = true
            }
        }
    }

    private func requestPreview() {
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            return
        }

        isLoading = true
        onPreview(trimmedPrompt) { result in
            DispatchQueue.main.async {
                self.previewText = result
                self.isLoading = false
                self.showPreview = true
                // Notify parent window about preview mode change
                self.onPreviewModeChanged(true)
            }
        }
    }
}

// Custom button styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.blue.opacity(0.8) : Color.blue)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.gray.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ModernTextFieldStyle: TextFieldStyle {
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
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
