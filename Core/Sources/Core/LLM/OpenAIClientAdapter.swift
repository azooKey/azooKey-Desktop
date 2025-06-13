import Foundation
import OpenAI

/// Adapter that wraps the OpenAI SDK to implement the LLMClient protocol.
public final class OpenAIClientAdapter: LLMClient {
    private let configuration: LLMConfiguration

    public init(configuration: LLMConfiguration) {
        self.configuration = configuration
    }

    public func sendRequest(_ request: LLMRequest, logger: ((String) -> Void)?) async throws -> [String] {
        let openAI = OpenAI(apiToken: configuration.apiKey)

        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .init(role: .system, content: "You are an assistant that predicts the continuation of short text.")!,
            .init(role: .user, content: """
                \(LLMPrompts.getPromptText(for: request.target))

                `\(request.prompt)<\(request.target)>`
                """)!
        ]
        
        let query = ChatQuery(
            messages: messages,
            model: .gpt3_5Turbo
        )

        do {
            let result = try await openAI.chats(query: query)
            
            guard let content = result.choices.first?.message.content else {
                throw LLMError.invalidResponseStructure("No content in response")
            }
            
            logger?("Response: \(content)")
            
            // Try to parse as JSON for predictions
            if let data = content.data(using: String.Encoding.utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let predictions = json["predictions"] as? [String] {
                return predictions
            }
            
            // Fallback: Split by newlines and clean up
            let lines = content.components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            return lines.isEmpty ? [content] : lines
            
        } catch {
            // Convert any error to LLMError
            if let description = (error as? LocalizedError)?.errorDescription {
                throw LLMError.parseError(description)
            }
            throw LLMError.parseError(error.localizedDescription)
        }
    }

    public func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String {
        let openAI = OpenAI(apiToken: configuration.apiKey)

        let query = ChatQuery(
            messages: [.init(role: .user, content: prompt)!],
            model: .gpt3_5Turbo,
            maxTokens: configuration.maxTokens,
            temperature: configuration.temperature
        )

        do {
            let result = try await openAI.chats(query: query)
            
            guard let content = result.choices.first?.message.content else {
                throw LLMError.invalidResponseStructure("No content in response")
            }
            
            return content
        } catch {
            // Convert any error to LLMError
            if let description = (error as? LocalizedError)?.errorDescription {
                throw LLMError.parseError(description)
            }
            throw LLMError.parseError(error.localizedDescription)
        }
    }
}