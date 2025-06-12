import Foundation

final class OpenAICompatibleClient: LLMClient {
    private let configuration: LLMConfiguration

    init(configuration: LLMConfiguration) {
        self.configuration = configuration
    }

    func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)?) async throws -> [String] {
        guard let endpointString = configuration.endpoint,
              let url = URL(string: endpointString) else {
            throw OpenAIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Use OpenAI-compatible format by default
        let body = request.toOpenAICompatibleJSON()
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            let truncatedBody = responseBody.count > 100 ? String(responseBody.prefix(97)) + "..." : responseBody
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: truncatedBody)
        }

        // Try OpenAI format first
        if let predictions = try? LLMResponseParser.parseOpenAICompatibleResponse(data, logger: logger), !predictions.isEmpty {
            return predictions
        }

        // Try simple JSON array format
        if let predictions = try? LLMResponseParser.parseSimpleJSONArray(data, logger: logger), !predictions.isEmpty {
            return predictions
        }

        throw OpenAIError.invalidResponseStructure("Unsupported response format")
    }

    func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String {
        guard let endpointString = configuration.endpoint,
              let url = URL(string: endpointString) else {
            throw OpenAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // OpenAI-compatible format
        let body = OpenAIRequest.createTextTransformJSON(
            prompt: prompt,
            modelName: modelName,
            maxTokens: configuration.maxTokens,
            temperature: configuration.temperature
        )

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            let truncatedBody = responseBody.count > 100 ? String(responseBody.prefix(97)) + "..." : responseBody
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: truncatedBody)
        }

        // Try OpenAI format
        if let text = try? LLMResponseParser.parseOpenAITextResponse(data) {
            return text
        }

        // Try plain text response
        guard let text = String(bytes: data, encoding: .utf8) else {
            throw OpenAIError.parseError("Failed to decode response as UTF-8")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Parsing methods moved to LLMResponseParser
}
