import Core
import Foundation

// OpenAI APIに送信するリクエスト構造体。
//
// - properties:
//    - prompt: 変換対象の前のテキスト
//    - target: 変換対象のテキスト
//    - modelName: モデル名
//
// - methods:
//    - toJSON(): リクエストをOpenAI APIに適したJSON形式に変換する。
struct OpenAIRequest {
    let prompt: String
    let target: String
    let modelName: String

    // リクエストをJSON形式に変換する関数
    func toJSON() -> [String: Any] {
        [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are an assistant that predicts the continuation of short text."],
                ["role": "user", "content": """
                    \(OpenAIPrompts.getPromptText(for: target))

                    `\(prompt)<\(target)>`
                    """]
            ],
            "response_format": [
                "type": "json_schema",
                "json_schema": [
                    "name": "PredictionResponse", // 必須のnameフィールド
                    "schema": [ // 必須のschemaフィールド
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
}

enum OpenAIError: LocalizedError {
    case invalidURL
    case noServerResponse
    case invalidResponseStatus(code: Int, body: String)
    case parseError(String)
    case invalidResponseStructure(Any)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not connect to OpenAI service. Please check your internet connection."
        case .noServerResponse:
            return "OpenAI service is not responding. Please try again later."
        case .invalidResponseStatus(let code, _):
            switch code {
            case 401:
                return "OpenAI API key is invalid. Please check your API key in preferences."
            case 403:
                return "Access denied by OpenAI. Please check your API key permissions."
            case 429:
                return "OpenAI rate limit exceeded. Please wait a moment and try again."
            case 500...599:
                return "OpenAI service is temporarily unavailable. Please try again later."
            default:
                return "OpenAI request failed. Please try again later."
            }
        case .parseError:
            return "Could not understand OpenAI response. Please try again."
        case .invalidResponseStructure:
            return "Received unexpected response from OpenAI. Please try again."
        }
    }
}

// OpenAI APIクライアント
enum OpenAIClient {
    private static let xpcClient = OpenAIXPCClient()
    // APIリクエストを送信する静的メソッド
    static func sendRequest(_ request: OpenAIRequest, apiKey: String, apiEndpoint: String? = nil, logger: ((String) -> Void)? = nil) async throws -> [String] {
        let configEndpoint = Config.OpenAiApiEndpoint().value
        let endpoint = if let apiEndpoint = apiEndpoint, !apiEndpoint.isEmpty {
            apiEndpoint
        } else if !configEndpoint.isEmpty {
            configEndpoint
        } else {
            Config.OpenAiApiEndpoint.default
        }

        // Try XPC first, fallback to direct implementation
        do {
            return try await xpcClient.sendRequest(
                prompt: request.prompt,
                mode: request.target,
                systemPrompt: "You are an assistant that predicts the continuation of short text.",
                model: request.modelName,
                apiKey: apiKey,
                endpoint: endpoint
            )
        } catch {
            logger?("XPC service unavailable, falling back to direct implementation: \(error)")
            return try await sendRequestDirect(request, apiKey: apiKey, apiEndpoint: apiEndpoint, logger: logger)
        }
    }

    // Direct implementation as fallback
    private static func sendRequestDirect(_ request: OpenAIRequest, apiKey: String, apiEndpoint: String? = nil, logger: ((String) -> Void)? = nil) async throws -> [String] {
        let configEndpoint = Config.OpenAiApiEndpoint().value
        let endpoint = if let apiEndpoint = apiEndpoint, !apiEndpoint.isEmpty {
            apiEndpoint
        } else if !configEndpoint.isEmpty {
            configEndpoint
        } else {
            Config.OpenAiApiEndpoint.default
        }

        guard let url = URL(string: endpoint) else {
            throw OpenAIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = request.toJSON()
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        // 非同期でリクエストを送信
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        // レスポンスの検証
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        // レスポンスデータの解析
        return try parseResponseData(data, logger: logger)
    }

    // レスポンスデータのパースを行う静的メソッド
    private static func parseResponseData(_ data: Data, logger: ((String) -> Void)? = nil) throws -> [String] {
        logger?("Received JSON response")

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            logger?("Failed to parse JSON response")
            throw OpenAIError.parseError("Failed to parse response")
        }

        guard let jsonDict = jsonObject as? [String: Any],
              let choices = jsonDict["choices"] as? [[String: Any]] else {
            throw OpenAIError.invalidResponseStructure(jsonObject)
        }

        var allPredictions: [String] = []
        for choice in choices {
            guard let message = choice["message"] as? [String: Any],
                  let contentString = message["content"] as? String else {
                continue
            }

            logger?("Raw content string: \(contentString)")

            guard let contentData = contentString.data(using: .utf8) else {
                logger?("Failed to convert `content` string to data")
                continue
            }

            do {
                guard let parsedContent = try JSONSerialization.jsonObject(with: contentData) as? [String: [String]],
                      let predictions = parsedContent["predictions"] else {
                    logger?("Failed to parse `content` as expected JSON dictionary: \(contentString)")
                    continue
                }

                logger?("Parsed predictions: \(predictions)")
                allPredictions.append(contentsOf: predictions)
            } catch {
                logger?("Error parsing JSON from `content`: \(error.localizedDescription)")
            }
        }

        return allPredictions
    }

    // Simple text transformation method for AI Transform feature
    static func sendTextTransformRequest(prompt: String, modelName: String, apiKey: String, apiEndpoint: String? = nil) async throws -> String {
        let configEndpoint = Config.OpenAiApiEndpoint().value
        let endpoint = if let apiEndpoint = apiEndpoint, !apiEndpoint.isEmpty {
            apiEndpoint
        } else if !configEndpoint.isEmpty {
            configEndpoint
        } else {
            Config.OpenAiApiEndpoint.default
        }

        // Try XPC first, fallback to direct implementation
        do {
            return try await xpcClient.sendTextTransformRequest(
                text: "",
                prompt: prompt,
                context: nil,
                model: modelName,
                apiKey: apiKey,
                endpoint: endpoint
            )
        } catch {
            return try await sendTextTransformRequestDirect(prompt: prompt, modelName: modelName, apiKey: apiKey, apiEndpoint: apiEndpoint)
        }
    }

    // Direct implementation as fallback
    private static func sendTextTransformRequestDirect(prompt: String, modelName: String, apiKey: String, apiEndpoint: String? = nil) async throws -> String {
        let configEndpoint = Config.OpenAiApiEndpoint().value
        let endpoint = if let apiEndpoint = apiEndpoint, !apiEndpoint.isEmpty {
            apiEndpoint
        } else if !configEndpoint.isEmpty {
            configEndpoint
        } else {
            Config.OpenAiApiEndpoint.default
        }

        guard let url = URL(string: endpoint) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that transforms text according to user instructions."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 150,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Send async request
        let (data, response) = try await URLSession.shared.data(for: request)

        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        // Parse response data
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let jsonDict = jsonObject as? [String: Any],
              let choices = jsonDict["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.invalidResponseStructure(jsonObject)
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ErrorUnion: Error {
    case nullError
    case double(any Error, any Error)
}

private struct ChatRequest: Codable {
    var model: String = "gpt-4o-mini"
    var messages: [Message] = []
}

private struct Message: Codable {
    enum Role: String, Codable {
        case user
        case system
        case assistant
    }
    var role: Role
    var content: String
}

private struct ChatSuccessResponse: Codable {
    var id: String
    var object: String
    var created: Int
    var model: String
    var choices: [Choice]

    struct Choice: Codable {
        var index: Int
        var logprobs: Double?
        var finishReason: String
        var message: Message
    }

    struct Usage: Codable {
        var promptTokens: Int
        var completionTokens: Int
        var totalTokens: Int
    }
}

private struct ChatFailureResponse: Codable, Error {
    var error: ErrorResponse
    struct ErrorResponse: Codable {
        var message: String
        var type: String
    }
}
