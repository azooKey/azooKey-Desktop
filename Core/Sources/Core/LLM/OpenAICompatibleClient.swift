import Foundation

/// Client for OpenAI-compatible APIs including Google Gemini and custom endpoints.
public final class OpenAICompatibleClient: LLMClient {
    private let configuration: LLMConfiguration

    public init(configuration: LLMConfiguration) {
        self.configuration = configuration
    }

    public func sendRequest(_ request: LLMRequest, logger: ((String) -> Void)?) async throws -> [String] {
        guard let endpointString = configuration.endpoint,
              let url = URL(string: endpointString) else {
            throw LLMError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use OpenAI-compatible format by default
        let body = request.toOpenAICompatibleJSON(promptFunction: LLMPrompts.getPromptText)
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            let truncatedBody = responseBody.count > 100 ? String(responseBody.prefix(97)) + "..." : responseBody
            throw LLMError.invalidResponseStatus(code: httpResponse.statusCode, body: truncatedBody)
        }

        // Try OpenAI format first
        if let predictions = try? LLMResponseParser.parseOpenAICompatibleResponse(data, logger: logger),
           !predictions.isEmpty {
            return predictions
        }

        // Try simple JSON array format
        if let predictions = try? LLMResponseParser.parseSimpleJSONArray(data, logger: logger), !predictions.isEmpty {
            return predictions
        }

        throw LLMError.invalidResponseStructure("Unsupported response format")
    }

    public func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String {
        guard let endpointString = configuration.endpoint,
              let url = URL(string: endpointString) else {
            throw LLMError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenAI-compatible format
        let body = LLMRequest.createTextTransformJSON(
            prompt: prompt,
            modelName: configuration.modelName,  // Use configuration model name
            maxTokens: configuration.maxTokens,
            temperature: configuration.temperature
        )

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            let truncatedBody = responseBody.count > 100 ? String(responseBody.prefix(97)) + "..." : responseBody
            throw LLMError.invalidResponseStatus(code: httpResponse.statusCode, body: truncatedBody)
        }

        // Try OpenAI format
        if let text = try? LLMResponseParser.parseOpenAITextResponse(data) {
            return text
        }

        // Try plain text response
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw LLMError.parseError("Failed to decode response as UTF-8")
        }
        return text
    }
}
