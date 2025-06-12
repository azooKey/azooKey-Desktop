import Foundation

protocol LLMClient {
    func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)?) async throws -> [String]
    func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String
}

struct LLMConfiguration {
    let provider: LLMProviderType
    let apiKey: String
    let modelName: String
    let endpoint: String?
    let maxTokens: Int
    let temperature: Double

    init(provider: LLMProviderType, apiKey: String, modelName: String, endpoint: String? = nil, maxTokens: Int = 150, temperature: Double = 0.7) {
        self.provider = provider
        self.apiKey = apiKey
        self.modelName = modelName
        self.endpoint = endpoint ?? Self.defaultEndpoint(for: provider)
        self.maxTokens = maxTokens
        self.temperature = temperature
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

    init(from string: String) {
        switch string.lowercased() {
        case "openai":
            self = .openai
        case "gemini":
            self = .gemini
        case "custom":
            self = .custom
        default:
            self = .openai
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
