import Foundation

class GeminiClient: LLMClient {
    private let configuration: LLMConfiguration

    init(configuration: LLMConfiguration) {
        self.configuration = configuration
    }

    func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)?) async throws -> [String] {
        // Use OpenAI-compatible endpoint
        guard let endpoint = configuration.endpoint else {
            throw OpenAIError.invalidURL
        }

        // Only log essential information

        guard let url = URL(string: endpoint) else {
            throw OpenAIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert request to use Gemini model name
        var modifiedRequest = request
        modifiedRequest.modelName = configuration.modelName

        let body = modifiedRequest.toJSON()
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Request body prepared

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        // Parse using the same logic as OpenAI
        return try LLMResponseParser.parseOpenAICompatibleResponse(data, logger: logger)
    }

    func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String {
        guard let endpoint = configuration.endpoint else {
            throw OpenAIError.invalidURL
        }

        guard let url = URL(string: endpoint) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that transforms text according to user instructions."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        // Parse OpenAI-compatible response
        return try LLMResponseParser.parseOpenAITextResponse(data)
    }

    // Parsing methods moved to LLMResponseParser
}
