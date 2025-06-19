import Foundation

/// Manager for creating and configuring LLM clients based on user preferences.
public final class LLMClientManager {
    /// Configuration provider protocol for dependency injection
    public protocol ConfigurationProvider {
        var llmProvider: String { get }
        var llmApiKey: String { get }
        var openAIModelName: String { get }
        var geminiModelName: String { get }
        var customModelName: String { get }
        var customEndpoint: String { get }
    }

    private let configProvider: ConfigurationProvider

    public init(configProvider: ConfigurationProvider) {
        self.configProvider = configProvider
    }

    /// Creates an LLM client based on current configuration.
    /// - Returns: Configured LLMClient instance or nil if configuration is invalid
    public func createClient() -> LLMClient? {
        let providerType = LLMProviderType(from: configProvider.llmProvider)
        let apiKey = configProvider.llmApiKey

        guard !apiKey.isEmpty else {
            return nil
        }

        let modelName = configProvider.openAIModelName  // All return the same value currently
        let endpoint: String? = providerType == .custom ? configProvider.customEndpoint : nil

        guard !modelName.isEmpty else {
            return nil
        }

        do {
            let configuration = try LLMConfiguration(
                provider: providerType,
                apiKey: apiKey,
                modelName: modelName,
                endpoint: endpoint
            )
            return LLMClientFactory.createClient(for: configuration)
        } catch {
            return nil
        }
    }

    /// Gets display name for the currently selected provider.
    /// - Returns: Localized display name for the provider
    public func getCurrentProviderDisplayName() -> String {
        let providerType = LLMProviderType(from: configProvider.llmProvider)
        return providerType.displayName
    }
}
