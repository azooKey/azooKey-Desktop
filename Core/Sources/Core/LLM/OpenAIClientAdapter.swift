import Foundation
import OpenAI

/// Adapter that wraps the OpenAI SDK to implement the LLMClient protocol.
/// Supports OpenAI and Gemini through the OpenAI package.
public final class OpenAIClientAdapter: LLMClient {
    private let configuration: LLMConfiguration
    private let openAI: OpenAI

    public init(configuration: LLMConfiguration) {
        self.configuration = configuration

        // Configure OpenAI client for different providers
        let openAIConfiguration: OpenAI.Configuration
        switch configuration.provider {
        case .openai:
            openAIConfiguration = OpenAI.Configuration(token: configuration.apiKey)
        case .gemini:
            // Use Gemini endpoint with parsing options for compatibility
            openAIConfiguration = OpenAI.Configuration(
                token: configuration.apiKey,
                host: "generativelanguage.googleapis.com/v1beta/openai",
                parsingOptions: .fillRequiredFieldIfKeyNotFound
            )
        case .custom:
            // This case should not happen as custom uses OpenAICompatibleClient
            openAIConfiguration = OpenAI.Configuration(token: configuration.apiKey)
        }

        self.openAI = OpenAI(configuration: openAIConfiguration)
    }

    public func sendRequest(_ request: LLMRequest, logger: ((String) -> Void)?) async throws -> [String] {

        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .init(role: .system, content: "You are an assistant that predicts the continuation of short text.")!,
            .init(role: .user, content: """
                \(LLMPrompts.getPromptText(for: request.target))

                `\(request.prompt)<\(request.target)>`
                """)!
        ]

        let query = ChatQuery(
            messages: messages,
            model: configuration.modelName
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

        let query = ChatQuery(
            messages: [.init(role: .user, content: prompt)!],
            model: configuration.modelName,
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
