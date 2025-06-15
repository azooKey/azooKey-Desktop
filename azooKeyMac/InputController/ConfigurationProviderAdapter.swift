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
        Config.LLMModelName().value
    }

    var geminiModelName: String {
        Config.LLMModelName().value
    }

    var customModelName: String {
        Config.LLMModelName().value
    }

    var customEndpoint: String {
        Config.CustomLLMEndpoint().value
    }
}
