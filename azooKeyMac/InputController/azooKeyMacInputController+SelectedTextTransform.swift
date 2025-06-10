//
//  azooKeyMacInputController+SelectedTextTransform.swift
//  azooKeyMac
//
//  Created by Claude on 2025/06/10.
//

import Cocoa
import Core
import Foundation
import InputMethodKit

// MARK: - Selected Text Transform Methods
extension azooKeyMacInputController {

    struct TextContext {
        let before: String
        let selected: String
        let after: String
    }

    @MainActor
    func getContextAroundSelection(client: IMKTextInput, selectedRange: NSRange, contextLength: Int = 200) -> TextContext {
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
                        let result = try await self.getTransformationPreview(
                            selectedText: selectedText,
                            prompt: prompt,
                            beforeContext: context.before,
                            afterContext: context.after
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
                let results = try await self.sendCustomPromptRequest(
                    prompt: systemPrompt,
                    modelName: modelName,
                    apiKey: apiKey
                )

                await MainActor.run {
                    self.segmentsManager.appendDebugMessage("transformSelectedText: API request completed, results: \(results)")
                }

                if let result = results.first {
                    await MainActor.run {
                        self.segmentsManager.appendDebugMessage("transformSelectedText: Result obtained: '\(result)'")
                        // Note: This method lacks the stored range information.
                        // Text replacement should be handled by showPromptInputWindow instead.
                        self.segmentsManager.appendDebugMessage("transformSelectedText: Note - This path should not be used for text replacement")
                    }
                } else {
                    await MainActor.run {
                        self.segmentsManager.appendDebugMessage("transformSelectedText: No results returned from API")
                    }
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
            self.segmentsManager.appendDebugMessage("replaceSelectedText: Starting system-level text replacement")

            // Method 1: Try system-level clipboard replacement (works better with web apps)
            self.replaceTextUsingSystemClipboard(newText: newText, storedRange: storedRange)

        } else {
            self.segmentsManager.appendDebugMessage("replaceSelectedText: Stored range has no length")
        }
    }

    @MainActor
    private func replaceTextUsingSystemClipboard(newText: String, storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Starting clipboard-based replacement")

        // Store the current clipboard content
        let pasteboard = NSPasteboard.general
        let originalClipboardContent = pasteboard.string(forType: .string)
        self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Backed up clipboard content")

        // Put the new text in clipboard
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)
        self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Set new text to clipboard")

        // First, select the text using the stored range
        guard self.client() != nil else {
            self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: No client available")
            return
        }

        // Approach: First reselect the text, then use system paste to replace
        self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Reselecting text and using system paste")

        // Step 1: Reselect the text using the stored range by simulating mouse selection
        self.reselectTextAndReplace(storedRange: storedRange, newText: newText)

        // Restore clipboard after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let originalContent = originalClipboardContent {
                pasteboard.clearContents()
                pasteboard.setString(originalContent, forType: .string)
                self.segmentsManager.appendDebugMessage("replaceTextUsingSystemClipboard: Restored clipboard content")
            }
        }
    }

    @MainActor
    private func reselectTextAndReplace(storedRange: NSRange, newText: String) {
        self.segmentsManager.appendDebugMessage("reselectTextAndReplace: Starting with range: \(storedRange)")

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("reselectTextAndReplace: No client available")
            return
        }

        // Method 1: Try to set the selection using IMK
        self.segmentsManager.appendDebugMessage("reselectTextAndReplace: Setting selection using IMK")
        client.setMarkedText("", selectionRange: storedRange, replacementRange: storedRange)

        // Small delay to ensure selection is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.segmentsManager.appendDebugMessage("reselectTextAndReplace: Selection should be set, now pasting")

            // Use system paste to replace the selected text
            self.simulateSystemPaste()

            // Verify success and only fallback if needed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let currentRange = client.selectedRange()
                let expectedLocation = storedRange.location + newText.count

                // Only use fallback if the paste didn't work (cursor not at expected location)
                if abs(currentRange.location - expectedLocation) > 5 {
                    self.segmentsManager.appendDebugMessage("reselectTextAndReplace: System paste may have failed, trying IMK fallback")
                    client.insertText(newText, replacementRange: storedRange)
                } else {
                    self.segmentsManager.appendDebugMessage("reselectTextAndReplace: System paste appears successful")
                }
            }
        }
    }

    @MainActor
    private func simulateSystemPaste() {
        self.segmentsManager.appendDebugMessage("simulateSystemPaste: Starting system paste simulation")

        // Create CGEvent source for system events
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            self.segmentsManager.appendDebugMessage("simulateSystemPaste: Failed to create event source")
            return
        }

        // Simulate Cmd+V to paste
        if let cmdVDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: true),
           let cmdVUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: false) {

            cmdVDown.flags = .maskCommand
            cmdVUp.flags = .maskCommand

            self.segmentsManager.appendDebugMessage("simulateSystemPaste: Simulating Cmd+V")
            cmdVDown.post(tap: .cghidEventTap)
            cmdVUp.post(tap: .cghidEventTap)

            self.segmentsManager.appendDebugMessage("simulateSystemPaste: Paste completed")
        }
    }

    @MainActor
    private func simulateSystemReplacement(storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("simulateSystemReplacement: Starting system event simulation")

        // Try to reselect the text using accessibility and then replace with paste
        self.attemptTextReselectionAndReplace(storedRange: storedRange)
    }

    @MainActor
    private func attemptTextReselectionAndReplace(storedRange: NSRange) {
        self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Attempting to reselect and replace text")

        guard let client = self.client() else {
            self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: No client available")
            return
        }

        // Try different methods to replace text

        // Method 1: Force selection and then use paste
        self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Method 1 - Force selection then paste")

        // Set selection to the stored range
        client.setMarkedText("", selectionRange: storedRange, replacementRange: storedRange)

        // Small delay to ensure selection is set
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            // Create CGEvent source for system events
            guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
                self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Failed to create event source")
                return
            }

            // Simulate Cmd+V to paste the new text
            if let cmdVDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: true),
               let cmdVUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: false) {

                cmdVDown.flags = .maskCommand
                cmdVUp.flags = .maskCommand

                self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Simulating Cmd+V paste")
                cmdVDown.post(tap: .cghidEventTap)
                cmdVUp.post(tap: .cghidEventTap)

                self.segmentsManager.appendDebugMessage("attemptTextReselectionAndReplace: Paste command sent")
            }
        }
    }

    // Custom prompt request for text transformation
    func sendCustomPromptRequest(prompt: String, modelName: String, apiKey: String) async throws -> [String] {
        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Starting API request to OpenAI")
        }

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Invalid URL")
            }
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that transforms text according to user instructions."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 150,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Sending request to OpenAI API")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Received response from API")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: No HTTP response")
            }
            throw OpenAIError.noServerResponse
        }

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: HTTP status code: \(httpResponse.statusCode)")
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: API error - Status: \(httpResponse.statusCode), Body: \(responseBody)")
            }
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let jsonDict = jsonObject as? [String: Any],
              let choices = jsonDict["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Failed to parse API response structure")
            }
            throw OpenAIError.invalidResponseStructure(jsonObject)
        }

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
            self.segmentsManager.appendDebugMessage("sendCustomPromptRequest: Successfully parsed result: '\(result)'")
        }

        return [result]
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
            throw NSError(domain: "TransformationError", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API is not enabled"])
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
            throw NSError(domain: "TransformationError", code: -2, userInfo: [NSLocalizedDescriptionKey: "No OpenAI API key configured"])
        }

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("getTransformationPreview: Sending preview request to API")
        }

        let modelName = Config.OpenAiModelName().value
        let results = try await self.sendCustomPromptRequest(
            prompt: systemPrompt,
            modelName: modelName,
            apiKey: apiKey
        )

        guard let result = results.first else {
            await MainActor.run {
                self.segmentsManager.appendDebugMessage("getTransformationPreview: No results returned from API")
            }
            throw NSError(domain: "TransformationError", code: -3, userInfo: [NSLocalizedDescriptionKey: "No results returned from API"])
        }

        await MainActor.run {
            self.segmentsManager.appendDebugMessage("getTransformationPreview: Preview result: '\(result)'")
        }

        return result
    }
}
