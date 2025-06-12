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
        guard Config.EnableOpenAiApiKey().value else {
            return nil
        }
        return createClient(
            provider: .openai,
            apiKey: Config.LLMApiKey().value,
            modelName: Config.OpenAiModelName().value
        )
    }

    private func createGeminiClient() -> LLMClient? {
        guard Config.EnableGeminiApiKey().value else {
            return nil
        }
        return createClient(
            provider: .gemini,
            apiKey: Config.LLMApiKey().value,
            modelName: Config.GeminiModelName().value
        )
    }

    private func createCustomClient() -> LLMClient? {
        createClient(
            provider: .custom,
            apiKey: Config.LLMApiKey().value,
            modelName: Config.OpenAiModelName().value,
            endpoint: Config.CustomLLMEndpoint().value
        )
    }

    private func createClient(provider: LLMProviderType, apiKey: String, modelName: String, endpoint: String? = nil) -> LLMClient? {
        do {
            let configuration = try LLMConfiguration(provider: provider, apiKey: apiKey, modelName: modelName, endpoint: endpoint)
            return LLMClientFactory.createClient(for: configuration)
        } catch {
            return nil
        }
    }
}
