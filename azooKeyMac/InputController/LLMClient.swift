import Foundation

protocol LLMClient {
    func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)?) async throws -> [String]
    func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String
}

enum LLMConfigurationError: LocalizedError {
    case invalidAPIKey
    case invalidModelName
    case invalidEndpoint
    case invalidMaxTokens
    case invalidTemperature

    var errorDescription: String? {
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

struct LLMConfiguration {
    let provider: LLMProviderType
    let apiKey: String
    let modelName: String
    let endpoint: String?
    let maxTokens: Int
    let temperature: Double

    init(provider: LLMProviderType, apiKey: String, modelName: String, endpoint: String? = nil, maxTokens: Int = 150, temperature: Double = 0.7) throws {
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

enum LLMProviderType {
    case openai
    case gemini
    case custom

    // 定数を定義
    private enum Constants {
        static let openai = "openai"
        static let gemini = "gemini"
        static let custom = "custom"
    }

    init(from string: String) {
        switch string.lowercased() {
        case Constants.openai:
            self = .openai
        case Constants.gemini:
            self = .gemini
        case Constants.custom:
            self = .custom
        default:
            self = .openai
        }
    }

    var stringValue: String {
        switch self {
        case .openai:
            return Constants.openai
        case .gemini:
            return Constants.gemini
        case .custom:
            return Constants.custom
        }
    }

    var displayName: String {
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

enum LLMClientFactory {
    static func createClient(for configuration: LLMConfiguration) -> LLMClient? {
        switch configuration.provider {
        case .openai:
            return OpenAIClientAdapter(configuration: configuration)
        case .gemini, .custom:
            return CustomLLMClient(configuration: configuration)
        }
    }
}
