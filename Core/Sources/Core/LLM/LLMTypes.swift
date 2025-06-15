import Foundation

/// LLM API request structure.
///
/// - properties:
///    - prompt: The text before the conversion target
///    - target: The text to be converted
///    - modelName: The model name to use
public struct LLMRequest {
    public let prompt: String
    public let target: String
    public var modelName: String

    public init(prompt: String, target: String, modelName: String) {
        self.prompt = prompt
        self.target = target
        self.modelName = modelName
    }

    /// Generates common JSON structure for OpenAI-compatible APIs
    public func toOpenAICompatibleJSON(promptFunction: (String) -> String) -> [String: Any] {
        [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are an assistant that predicts the continuation of short text."],
                ["role": "user", "content": """
                    \(promptFunction(target))

                    `\(prompt)<\(target)>`
                    """]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "PredictionResponse",
                    "schema": [
                        "type": "object",
                        "properties": [
                            "predictions": [
                                "type": "array",
                                "items": [
                                    "type": "string",
                                    "description": "Replacement text"
                                ]
                            ]
                        ],
                        "required": ["predictions"],
                        "additionalProperties": false
                    ]
                ]
            ]
        ]
    }

    /// Creates JSON structure for text transformation requests
    public static func createTextTransformJSON(prompt: String, modelName: String, maxTokens: Int = 150, temperature: Double = 0.7) -> [String: Any] {
        [
            "model": modelName,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": maxTokens,
            "temperature": temperature
        ]
    }
}

public enum LLMError: LocalizedError {
    case invalidURL
    case noServerResponse
    case invalidResponseStatus(code: Int, body: String)
    case parseError(String)
    case invalidResponseStructure(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not connect to LLM service. Please check your internet connection."
        case .noServerResponse:
            return "LLM service is not responding. Please try again later."
        case .invalidResponseStatus(let code, _):
            switch code {
            case 401:
                return "API key is invalid. Please check your API key in preferences."
            case 403:
                return "Access denied. Please check your API key permissions."
            case 429:
                return "Rate limit exceeded. Please wait a moment and try again."
            case 500...599:
                return "Service is temporarily unavailable. Please try again later."
            default:
                return "Request failed. Please try again later."
            }
        case .parseError:
            return "Could not understand response. Please try again."
        case .invalidResponseStructure:
            return "Received unexpected response. Please try again."
        }
    }
}