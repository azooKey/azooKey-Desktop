import Foundation

class CustomLLMClient: LLMClient {
    private let configuration: CustomConfiguration

    init(configuration: CustomConfiguration) {
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
        let body = request.toJSON()
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        // Try OpenAI format first
        if let predictions = try? parseOpenAIFormat(data, logger: logger), !predictions.isEmpty {
            return predictions
        }

        // Try simple JSON array format
        if let predictions = try? parseSimpleJSONArray(data, logger: logger), !predictions.isEmpty {
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

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIError.noServerResponse
        }

        guard httpResponse.statusCode == 200 else {
            let responseBody = String(bytes: data, encoding: .utf8) ?? "Body is not encoded in UTF-8"
            throw OpenAIError.invalidResponseStatus(code: httpResponse.statusCode, body: responseBody)
        }

        // Try OpenAI format
        if let text = try? parseOpenAITextResponse(data) {
            return text
        }

        // Try plain text response
        let text = String(decoding: data, as: UTF8.self)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseOpenAIFormat(_ data: Data, logger: ((String) -> Void)?) throws -> [String] {
        let jsonObject = try JSONSerialization.jsonObject(with: data)

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

    private func parseSimpleJSONArray(_ data: Data, logger: ((String) -> Void)?) throws -> [String] {
        let jsonObject = try JSONSerialization.jsonObject(with: data)

        if let predictions = jsonObject as? [String] {
            logger?("Parsed simple JSON array: \(predictions)")
            return predictions
        }

        if let jsonDict = jsonObject as? [String: Any],
           let predictions = jsonDict["predictions"] as? [String] {
            logger?("Parsed predictions from object: \(predictions)")
            return predictions
        }

        throw OpenAIError.invalidResponseStructure(jsonObject)
    }

    private func parseOpenAITextResponse(_ data: Data) throws -> String {
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
