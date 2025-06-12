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

        let apiKey = Config.LLMApiKey().value
        let modelName = Config.OpenAiModelName().value

        do {
            let configuration = try LLMConfiguration(provider: .openai, apiKey: apiKey, modelName: modelName)
            return LLMClientFactory.createClient(for: configuration)
        } catch {
            print("OpenAI設定エラー: \(error.localizedDescription)")
            return nil
        }
    }

    private func createGeminiClient() -> LLMClient? {
        let enableGemini = Config.EnableGeminiApiKey().value
        guard enableGemini else {
            return nil
        }

        let apiKey = Config.LLMApiKey().value
        let modelName = Config.GeminiModelName().value

        do {
            let configuration = try LLMConfiguration(provider: .gemini, apiKey: apiKey, modelName: modelName)
            return LLMClientFactory.createClient(for: configuration)
        } catch {
            print("Gemini設定エラー: \(error.localizedDescription)")
            return nil
        }
    }

    private func createCustomClient() -> LLMClient? {
        let endpoint = Config.CustomLLMEndpoint().value
        let apiKey = Config.LLMApiKey().value
        let modelName = Config.OpenAiModelName().value

        do {
            let configuration = try LLMConfiguration(provider: .custom, apiKey: apiKey, modelName: modelName, endpoint: endpoint)
            return LLMClientFactory.createClient(for: configuration)
        } catch {
            print("カスタムLLM設定エラー: \(error.localizedDescription)")
            return nil
        }
    }
}
