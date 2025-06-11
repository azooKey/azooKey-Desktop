import Foundation

class LLMClientManager {
    static let shared = LLMClientManager()

    private init() {}

    func createClient() -> LLMClient? {
        let provider = Config.LLMProvider().value
        let providerType = LLMProviderType(from: provider)

        switch providerType {
        case .openai:
            return createOpenAIClient()
        case .gemini:
            return createGeminiClient()
        case .custom:
            return createCustomClient()
        }
    }

    private func createOpenAIClient() -> LLMClient? {
        let enableOpenAI = Config.EnableOpenAiApiKey().value
        guard enableOpenAI else {
            return nil
        }

        let apiKey = Config.OpenAiApiKey().value
        guard !apiKey.isEmpty else {
            return nil
        }

        let modelName = Config.OpenAiModelName().value
        let configuration = LLMConfiguration(provider: .openai, apiKey: apiKey, modelName: modelName)
        return LLMClientFactory.createClient(for: configuration)
    }

    private func createGeminiClient() -> LLMClient? {
        let enableGemini = Config.EnableGeminiApiKey().value
        guard enableGemini else {
            return nil
        }

        let apiKey = Config.GeminiApiKey().value
        guard !apiKey.isEmpty else {
            return nil
        }

        let modelName = Config.GeminiModelName().value
        let configuration = LLMConfiguration(provider: .gemini, apiKey: apiKey, modelName: modelName)
        return LLMClientFactory.createClient(for: configuration)
    }

    private func createCustomClient() -> LLMClient? {
        let endpoint = Config.CustomLLMEndpoint().value
        guard !endpoint.isEmpty else {
            return nil
        }

        // Custom endpoints use OpenAI API format
        let apiKey = Config.OpenAiApiKey().value
        guard !apiKey.isEmpty else {
            return nil
        }

        let modelName = Config.OpenAiModelName().value
        let configuration = LLMConfiguration(provider: .custom, apiKey: apiKey, modelName: modelName, endpoint: endpoint)
        return LLMClientFactory.createClient(for: configuration)
    }
}
