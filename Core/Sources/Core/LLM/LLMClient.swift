import Foundation

/// Protocol defining the interface for LLM (Large Language Model) clients.
/// Supports multiple providers including OpenAI, Google Gemini, and custom OpenAI-compatible APIs.
public protocol LLMClient {
    /// Sends a structured prediction request to the LLM service.
    /// - Parameters:
    ///   - request: The LLM request containing prompt and target information
    ///   - logger: Optional logging function for debugging purposes
    /// - Returns: Array of prediction strings returned by the LLM
    /// - Throws: LLMError if the request fails or response is invalid
    func sendRequest(_ request: LLMRequest, logger: ((String) -> Void)?) async throws -> [String]

    /// Sends a simple text transformation request to the LLM service.
    /// - Parameters:
    ///   - prompt: The text prompt to send to the LLM
    ///   - modelName: The model name to use (note: some implementations may override this with configuration)
    /// - Returns: Transformed text response from the LLM
    /// - Throws: LLMError if the request fails or response is invalid
    func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String
}

public enum LLMConfigurationError: LocalizedError {
    case invalidAPIKey
    case invalidModelName
    case invalidEndpoint
    case invalidMaxTokens
    case invalidTemperature

    public var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "APIキーが無効です"
        case .invalidModelName:
            return "モデル名が無効です"
        case .invalidEndpoint:
            return "エンドポイントURLが無効です"
        case .invalidMaxTokens:
            return "最大トークン数は1以上である必要があります"
        case .invalidTemperature:
            return "温度は0.0から2.0の範囲である必要があります"
        }
    }
}

/// Configuration structure for LLM clients containing all necessary parameters.
public struct LLMConfiguration {
    /// The LLM provider type (OpenAI, Gemini, or Custom)
    public let provider: LLMProviderType
    /// API key for authentication
    public let apiKey: String
    /// Model name to use for requests
    public let modelName: String
    /// Optional custom endpoint URL (used for custom providers and Gemini)
    public let endpoint: String?
    /// Maximum number of tokens to generate (default: 150)
    public let maxTokens: Int
    /// Sampling temperature for response generation (0.0-2.0, default: 0.7)
    public let temperature: Double

    /// Creates a new LLM configuration with validation.
    /// - Parameters:
    ///   - provider: The LLM provider type
    ///   - apiKey: API key for authentication (will be trimmed of whitespace)
    ///   - modelName: Model name to use (will be trimmed of whitespace)
    ///   - endpoint: Optional custom endpoint URL (auto-configured for some providers)
    ///   - maxTokens: Maximum tokens to generate (must be > 0)
    ///   - temperature: Sampling temperature (must be 0.0-2.0)
    /// - Throws: LLMConfigurationError if any parameter is invalid
    public init(
        provider: LLMProviderType,
        apiKey: String,
        modelName: String,
        endpoint: String? = nil,
        maxTokens: Int = 150,
        temperature: Double = 0.7
    ) throws {
        // APIキーの検証
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw LLMConfigurationError.invalidAPIKey
        }

        // モデル名の検証
        let trimmedModelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelName.isEmpty else {
            throw LLMConfigurationError.invalidModelName
        }

        // エンドポイントの検証（カスタムプロバイダーの場合）
        let finalEndpoint = endpoint ?? Self.defaultEndpoint(for: provider)
        if let endpointString = finalEndpoint {
            guard Self.isValidEndpoint(endpointString) else {
                throw LLMConfigurationError.invalidEndpoint
            }
        }

        // maxTokensの検証
        guard maxTokens > 0 else {
            throw LLMConfigurationError.invalidMaxTokens
        }

        // temperatureの検証
        guard temperature >= 0.0 && temperature <= 2.0 else {
            throw LLMConfigurationError.invalidTemperature
        }

        self.provider = provider
        self.apiKey = trimmedAPIKey
        self.modelName = trimmedModelName
        self.endpoint = finalEndpoint
        self.maxTokens = maxTokens
        self.temperature = temperature
    }

    private static func isValidEndpoint(_ endpoint: String) -> Bool {
        guard let url = URL(string: endpoint),
              let scheme = url.scheme,
              scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    private static func defaultEndpoint(for provider: LLMProviderType) -> String? {
        switch provider {
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .openai, .custom:
            return nil
        }
    }
}

/// Enumeration of supported LLM provider types.
public enum LLMProviderType: String, CaseIterable {
    /// OpenAI provider (GPT models)
    case openai = "openai"
    /// Google Gemini provider
    case gemini = "gemini"
    /// Custom OpenAI-compatible provider
    case custom = "custom"

    public init(from string: String) {
        self = LLMProviderType(rawValue: string.lowercased()) ?? .openai
    }

    public var displayName: String {
        switch self {
        case .openai:
            return "OpenAI"
        case .gemini:
            return "Google Gemini"
        case .custom:
            return "カスタム"
        }
    }
}

public enum LLMClientFactory {
    public static func createClient(for configuration: LLMConfiguration) -> LLMClient? {
        switch configuration.provider {
        case .openai:
            return OpenAIClientAdapter(configuration: configuration)
        case .gemini, .custom:
            return OpenAICompatibleClient(configuration: configuration)
        }
    }
}
