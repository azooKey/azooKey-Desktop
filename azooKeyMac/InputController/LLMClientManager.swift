import Core
import Foundation

/// Wrapper that provides access to Core's LLMClientManager with the app's configuration
final class LLMClientManager {
    static let shared = Core.LLMClientManager(configProvider: ConfigurationProviderAdapter())

    private init() {}
}