import Foundation
import Core

/// Adapter that bridges the main app's Config system to Core's LLMClientManager.ConfigurationProvider
struct ConfigurationProviderAdapter: LLMClientManager.ConfigurationProvider {
    var llmProvider: String {
        Config.LLMProvider.value
    }
    
    var llmApiKey: String {
        Config.LLMApiKey.value
    }
    
    var openAIModelName: String {
        Config.OpenAIModelName.value
    }
    
    var geminiModelName: String {
        Config.GeminiModelName.value
    }
    
    var customModelName: String {
        Config.CustomModelName.value
    }
    
    var customEndpoint: String {
        Config.CustomEndpoint.value
    }
}