import Foundation

class LLMClientManager {
    static let shared = LLMClientManager()

    private init() {}

    func createClient() -> LLMClient? {
        let provider = Config.LLMProvider().value
        let providerType = LLMProviderType(from: provider)
        print("DEBUG: LLM Provider = \(provider), Type = \(providerType)")

        switch providerType {
        case .openai:
            print("DEBUG: Creating OpenAI client")
            return createOpenAIClient()
        case .gemini:
            print("DEBUG: Creating Gemini client")
            return createGeminiClient()
        case .custom:
            print("DEBUG: Creating Custom client")
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
        let configuration = OpenAIConfiguration(apiKey: apiKey, modelName: modelName)
        return LLMClientFactory.createClient(for: .openai, configuration: configuration)
    }

    private func createGeminiClient() -> LLMClient? {
        let enableGemini = Config.EnableGeminiApiKey().value
        print("DEBUG: EnableGeminiApiKey = \(enableGemini)")
        guard enableGemini else {
            print("DEBUG: Gemini not enabled")
            return nil
        }

        let apiKey = Config.GeminiApiKey().value
        print("DEBUG: GeminiApiKey present = \(!apiKey.isEmpty)")
        guard !apiKey.isEmpty else {
            print("DEBUG: Gemini API key is empty")
            return nil
        }

        let modelName = Config.GeminiModelName().value
        print("DEBUG: GeminiModelName = \(modelName)")
        let configuration = GeminiConfiguration(apiKey: apiKey, modelName: modelName)
        let client = LLMClientFactory.createClient(for: .gemini, configuration: configuration)
        print("DEBUG: Gemini client created = \(client != nil)")
        return client
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
        let configuration = CustomConfiguration(apiKey: apiKey, modelName: modelName, endpoint: endpoint)
        return LLMClientFactory.createClient(for: .custom, configuration: configuration)
    }
}
