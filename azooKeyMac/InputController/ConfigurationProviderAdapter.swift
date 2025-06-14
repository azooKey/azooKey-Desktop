import Core
import Foundation

/// Adapter that bridges the main app's Config system to Core's LLMClientManager.ConfigurationProvider
struct ConfigurationProviderAdapter: Core.LLMClientManager.ConfigurationProvider {
    var llmProvider: String {
        Config.LLMProvider().value
    }

    var llmApiKey: String {
        Config.LLMApiKey().value
    }

    var openAIModelName: String {
        Config.OpenAiModelName().value
    }

    var geminiModelName: String {
        Config.GeminiModelName().value
    }

    var customModelName: String {
        ""  // No custom model name config item exists yet
    }

    var customEndpoint: String {
        Config.CustomLLMEndpoint().value
    }
}
