import Foundation

protocol LLMClient {
    func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)?) async throws -> [String]
    func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String
}

protocol LLMClientConfiguration {
    var apiKey: String { get }
    var modelName: String { get }
    var endpoint: String? { get }
}

struct OpenAIConfiguration: LLMClientConfiguration {
    var apiKey: String
    var modelName: String
    var endpoint: String?
}

struct GeminiConfiguration: LLMClientConfiguration {
    var apiKey: String
    var modelName: String
    var endpoint: String?
}

struct CustomConfiguration: LLMClientConfiguration {
    var apiKey: String
    var modelName: String
    var endpoint: String?
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
    static func createClient(for provider: LLMProviderType, configuration: LLMClientConfiguration) -> LLMClient? {
        switch provider {
        case .openai:
            guard let config = configuration as? OpenAIConfiguration else {
                return nil
            }
            return OpenAIClientAdapter(configuration: config)
        case .gemini:
            guard let config = configuration as? GeminiConfiguration else {
                return nil
            }
            return GeminiClient(configuration: config)
        case .custom:
            guard let config = configuration as? CustomConfiguration else {
                return nil
            }
            return CustomLLMClient(configuration: config)
        }
    }
}
