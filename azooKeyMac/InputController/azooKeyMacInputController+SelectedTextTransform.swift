import Cocoa
import Core
import Foundation
import InputMethodKit

// MARK: - Selected Text Transform Methods
extension azooKeyMacInputController {

    // MARK: - Constants
    private enum Constants {
        static let defaultContextLength = 200
        static let cursorPositionTolerance = 2
        static let replacementVerificationDelay = 0.1
        static let clipboardDelay = 0.05
        static let clipboardRestoreDelay = 0.3
    }

    struct TextContext {
        let before: String
        let selected: String
        let after: String
    }

    private var endpoint: String {
        if Config.OpenAiApiEndpoint().value.isEmpty {
            Config.OpenAiApiEndpoint.default
        } else {
            Config.OpenAiApiEndpoint().value
        }
    }

    @MainActor
    func getContextAroundSelection(client: IMKTextInput, selectedRange: NSRange, contextLength: Int = Constants.defaultContextLength) -> TextContext {
        // Get the selected text
        var actualRange = NSRange()
        let selectedText = client.string(from: selectedRange, actualRange: &actualRange) ?? ""

        // Calculate context ranges
        let documentLength = client.length()

        // Get text before selection (up to contextLength characters)
        let beforeStart = max(0, selectedRange.location - contextLength)
        let beforeLength = selectedRange.location - beforeStart
        let beforeRange = NSRange(location: beforeStart, length: beforeLength)

        // Get text after selection (up to contextLength characters)
        let afterStart = selectedRange.location + selectedRange.length
        let afterLength = min(contextLength, documentLength - afterStart)
        let afterRange = NSRange(location: afterStart, length: afterLength)

        // Extract context strings
        var beforeActualRange = NSRange()
        let beforeText = (beforeLength > 0) ? (client.string(from: beforeRange, actualRange: &beforeActualRange) ?? "") : ""

        var afterActualRange = NSRange()
        let afterText = (afterLength > 0) ? (client.string(from: afterRange, actualRange: &afterActualRange) ?? "") : ""

        self.segmentsManager.appendDebugMessage("getContextAroundSelection: Before context: '\(beforeText)'")
        self.segmentsManager.appendDebugMessage("getContextAroundSelection: Selected text: '\(selectedText)'")
        self.segmentsManager.appendDebugMessage("getContextAroundSelection: After context: '\(afterText)'")

        return TextContext(before: beforeText, selected: selectedText, after: afterText)
    }

    @MainActor
    func showPromptInputWindow() {
        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Starting")

        // Set flag to prevent recursive calls
        self.isPromptWindowVisible = true

        // Get selected text
        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("showPromptInputWindow: No client available")
            self.isPromptWindowVisible = false
            return
        }

        let selectedRange = client.selectedRange()
        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Selected range in window: \(selectedRange)")

        guard selectedRange.length > 0 else {
            self.segmentsManager.appendDebugMessage("showPromptInputWindow: No selected text in window")
            return
        }

        var actualRange = NSRange()
        guard let selectedText = client.string(from: selectedRange, actualRange: &actualRange) else {
            self.segmentsManager.appendDebugMessage("showPromptInputWindow: Failed to get selected text")
            return
        }

        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Selected text: '\(selectedText)'")
        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Storing selected range for later use: \(selectedRange)")

        // Get context around selection
        let context = self.getContextAroundSelection(client: client, selectedRange: selectedRange)

        // Store the selected range and current app info for later use
        let storedSelectedRange = selectedRange
        let currentApp = NSWorkspace.shared.frontmostApplication

        // Get cursor position for window placement
        var cursorLocation = NSPoint.zero
        var rect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        cursorLocation = rect.origin

        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Cursor location: \(cursorLocation)")

        // Show prompt input window with preview functionality
        self.promptInputWindow.showPromptInput(
            at: cursorLocation,
            onPreview: { [weak self] prompt, callback in
                guard let self = self else {
                    return
                }
                self.segmentsManager.appendDebugMessage("showPromptInputWindow: Preview requested for prompt: '\(prompt)'")

                Task {
                    do {
                        // Check if context should be included
                        let includeContext = Config.IncludeContextInAITransform().value
                        let result = try await self.getTransformationPreview(
                            selectedText: selectedText,
                            prompt: prompt,
                            beforeContext: includeContext ? context.before : "",
                            afterContext: includeContext ? context.after : ""
                        )
                        callback(result)
                    } catch {
                        await MainActor.run {
                            self.segmentsManager.appendDebugMessage("showPromptInputWindow: Preview error: \(error)")
                        }
                        callback("Error: \(error.localizedDescription)")
                    }
                }
            },
            onApply: { [weak self] transformedText in
                guard let self = self else {
                    return
                }
                self.segmentsManager.appendDebugMessage("showPromptInputWindow: Applying transformed text: '\(transformedText)'")

                // Close the window first, then restore focus and replace text
                self.promptInputWindow.close()

                // Restore focus to the original app
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let app = currentApp {
                        app.activate(options: [])
                        self.segmentsManager.appendDebugMessage("showPromptInputWindow: Restored focus to original app")
                    }

                    // Replace text after focus is restored
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.replaceSelectedText(with: transformedText, usingRange: storedSelectedRange)
                    }
                }
            },
            completion: { [weak self] prompt in
                self?.segmentsManager.appendDebugMessage("showPromptInputWindow: Window closed with prompt: \(prompt ?? "nil")")
                self?.isPromptWindowVisible = false
            }
        )
    }

    @MainActor
    func transformSelectedText(selectedText: String, prompt: String, beforeContext: String = "", afterContext: String = "") {
        self.segmentsManager.appendDebugMessage("transformSelectedText: Starting with text '\(selectedText)' and prompt '\(prompt)'")

        guard Config.EnableOpenAiApiKey().value else {
            self.segmentsManager.appendDebugMessage("transformSelectedText: OpenAI API is not enabled")
            return
        }

        self.segmentsManager.appendDebugMessage("transformSelectedText: OpenAI API is enabled, starting request")

        Task {
            do {
                // Create custom prompt for text transformation with context
                var systemPrompt = """
                Transform the given text according to the user's instructions.
                Return only the transformed text without any additional explanation or formatting.
                """

                // Add context if available
                if !beforeContext.isEmpty || !afterContext.isEmpty {
                    systemPrompt += "\n\nContext information:"
                    if !beforeContext.isEmpty {
                        systemPrompt += "\nText before: ...\(beforeContext)"
                    }
                    systemPrompt += "\nText to transform: \(selectedText)"
                    if !afterContext.isEmpty {
                        systemPrompt += "\nText after: \(afterContext)..."
                    }
                } else {
                    systemPrompt += "\n\nText to transform: \(selectedText)"
                }

                systemPrompt += "\n\nUser instructions: \(prompt)"

                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: Created system prompt")
                }

                // Get API key from Config
                let apiKey = Config.OpenAiApiKey().value
                guard !apiKey.isEmpty else {
                    await MainActor.run {
                        self.segmentsManager.appendDebugMessage("transformSelectedText: No OpenAI API key configured")
                    }
                    return
                }

                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: API key found, making request")
                }

                let modelName = Config.OpenAiModelName().value
                let result = try await OpenAIClient.sendTextTransformRequest(
                    prompt: systemPrompt,
                    modelName: modelName,
                    apiKey: apiKey,
                    apiEndpoint: self.endpoint
                )

                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: API request completed, result: \(result)")
                    self.segmentsManager.appendDebugMessage("transformSelectedText: Result obtained: '\(result)'")
                    // Note: This method lacks the stored range information.
                    // Text replacement should be handled by showPromptInputWindow instead.
                    self.segmentsManager.appendDebugMessage("transformSelectedText: Note - This path should not be used for text replacement")
                }
            } catch {
                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: Error occurred: \(error)")
                }
            }
        }
    }

    @MainActor
    func replaceSelectedText(with newText: String, usingRange storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("replaceSelectedText: Starting with new text: '\(newText)'")
        self.segmentsManager.appendDebugMessage("replaceSelectedText: Using stored range: \(storedRange)")

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("replaceSelectedText: No client available")
            return
        }

        // Check current selection for comparison
        let currentSelectedRange = client.selectedRange()
        self.segmentsManager.appendDebugMessage("replaceSelectedText: Current selected range: \(currentSelectedRange)")
        self.segmentsManager.appendDebugMessage("replaceSelectedText: Stored range to use: \(storedRange)")

        if storedRange.length > 0 {
            self.segmentsManager.appendDebugMessage("replaceSelectedText: Starting text replacement")

            // Simplified approach: Try IMK first, fallback to clipboard if needed
            if !self.replaceTextUsingIMK(newText: newText, storedRange: storedRange) {
                self.replaceTextUsingClipboard(newText: newText, storedRange: storedRange)
            }
        } else {
            self.segmentsManager.appendDebugMessage("replaceSelectedText: Stored range has no length")
        }
    }

    // Simplified replacement methods

    @MainActor
    private func replaceTextUsingIMK(newText: String, storedRange: NSRange) -> Bool {
        self.segmentsManager.appendDebugMessage("replaceTextUsingIMK: Attempting IMK text replacement")

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("replaceTextUsingIMK: No client available")
            return false
        }

        // Try direct replacement using IMK
        client.insertText(newText, replacementRange: storedRange)

        // Verify the replacement worked by checking cursor position
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.replacementVerificationDelay) {
            let currentRange = client.selectedRange()
            let expectedLocation = storedRange.location + newText.count

            if abs(currentRange.location - expectedLocation) <= Constants.cursorPositionTolerance {
                self.segmentsManager.appendDebugMessage("replaceTextUsingIMK: IMK replacement appears successful")
            } else {
                self.segmentsManager.appendDebugMessage("replaceTextUsingIMK: IMK replacement may have failed")
            }
        }

        return true // Assume success, fallback will handle failures
    }

    @MainActor
    private func replaceTextUsingClipboard(newText: String, storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("replaceTextUsingClipboard: Starting clipboard-based replacement")

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("replaceTextUsingClipboard: No client available")
            return
        }

        // Store and set clipboard
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)

        // Set selection and paste
        client.setMarkedText("", selectionRange: storedRange, replacementRange: storedRange)

        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.clipboardDelay) {
            // Simulate Cmd+V
            if let source = CGEventSource(stateID: .hidSystemState),
               let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
               let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {

                cmdVDown.flags = .maskCommand
                cmdVUp.flags = .maskCommand
                cmdVDown.post(tap: .cghidEventTap)
                cmdVUp.post(tap: .cghidEventTap)
            }

            // Restore clipboard after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.clipboardRestoreDelay) {
                if let original = originalContent {
                    pasteboard.clearContents()
                    pasteboard.setString(original, forType: .string)
                }
            }
        }
    }

    // Get transformation preview without applying it
    func getTransformationPreview(selectedText: String, prompt: String, beforeContext: String = "", afterContext: String = "") async throws -> String {
        await MainActor.run {
            self.segmentsManager.appendDebugMessage("getTransformationPreview: Starting preview request")
        }

        guard Config.EnableOpenAiApiKey().value else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("getTransformationPreview: OpenAI API is not enabled")
            }
            throw NSError(domain: "TransformationError", code: -1, userInfo: [NSLocalizedDescriptionKey: "AI transformation is not available. Please enable OpenAI API in preferences."])
        }

        // Create custom prompt for text transformation with context
        var systemPrompt = """
        Transform the given text according to the user's instructions.
        Return only the transformed text without any additional explanation or formatting.
        """

        // Add context if available
        if !beforeContext.isEmpty || !afterContext.isEmpty {
            systemPrompt += "\n\nContext information:"
            if !beforeContext.isEmpty {
                systemPrompt += "\nText before: ...\(beforeContext)"
            }
            systemPrompt += "\nText to transform: \(selectedText)"
            if !afterContext.isEmpty {
                systemPrompt += "\nText after: \(afterContext)..."
            }
        } else {
            systemPrompt += "\n\nText to transform: \(selectedText)"
        }

        systemPrompt += "\n\nUser instructions: \(prompt)"

        // Get API key from Config
        let apiKey = Config.OpenAiApiKey().value
        guard !apiKey.isEmpty else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("getTransformationPreview: No OpenAI API key configured")
            }
            throw NSError(domain: "TransformationError", code: -2, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key is missing. Please configure your API key in preferences."])
        }

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("getTransformationPreview: Sending preview request to API")
        }

        let modelName = Config.OpenAiModelName().value
        let result = try await OpenAIClient.sendTextTransformRequest(
            prompt: systemPrompt,
            modelName: modelName,
            apiKey: apiKey,
            apiEndpoint: self.endpoint
        )

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("getTransformationPreview: Preview result: '\(result)'")
        }

        return result
    }
}
