//
//  OpenAIService.swift
//  azooKeyMacOpenAIService
//

import Core
import Foundation

class OpenAIService: NSObject, OpenAIServiceProtocol {
    func sendRequest(
        prompt: String,
        mode: String,
        systemPrompt: String,
        model: String,
        apiKey: String,
        endpoint: String?,
        with reply: @escaping (String?, Error?) -> Void
    ) {
        Task {
            do {
                let result = try await performRequest(
                    prompt: prompt,
                    mode: mode,
                    systemPrompt: systemPrompt,
                    model: model,
                    apiKey: apiKey,
                    endpoint: endpoint
                )
                reply(result, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    func sendTextTransformRequest(
        text: String,
        prompt: String,
        context: String?,
        model: String,
        apiKey: String,
        endpoint: String?,
        with reply: @escaping (String?, Error?) -> Void
    ) {
        Task {
            do {
                let result = try await performTextTransformRequest(
                    text: text,
                    prompt: prompt,
                    context: context,
                    model: model,
                    apiKey: apiKey,
                    endpoint: endpoint
                )
                reply(result, nil)
            } catch {
                reply(nil, error)
            }
        }
    }

    private func performRequest(
        prompt: String,
        mode: String,
        systemPrompt: String,
        model: String,
        apiKey: String,
        endpoint: String?
    ) async throws -> String {
        let baseEndpoint = endpoint ?? "https://api.openai.com/v1"
        let url = URL(string: "\(baseEndpoint)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build the user content with prompt template
        let promptText = OpenAIPrompts.getPromptText(for: mode)
        let userContent = """
            \(promptText)

            `\(prompt)<\(mode)>`
            """

        let messages = [
            ["role": "system", "content": "You are an assistant that predicts the continuation of short text."],
            ["role": "user", "content": userContent]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
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

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OpenAIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: responseBody])
        }

        // Parse the JSON response
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let contentString = message["content"] as? String,
           let contentData = contentString.data(using: .utf8),
           let parsedContent = try JSONSerialization.jsonObject(with: contentData) as? [String: [String]],
           let predictions = parsedContent["predictions"] {
            return predictions.joined(separator: "\n")
        }

        throw NSError(domain: "OpenAIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
    }

    private func performTextTransformRequest(
        text: String,
        prompt: String,
        context: String?,
        model: String,
        apiKey: String,
        endpoint: String?
    ) async throws -> String {
        let baseEndpoint = endpoint ?? "https://api.openai.com/v1"
        let url = URL(string: "\(baseEndpoint)/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let systemPrompt = "You are a helpful assistant that transforms text based on user instructions. Only output the transformed text without any explanation."

        var userMessage = "Transform the following text according to this instruction: \(prompt)\n\nText to transform: \(text)"
        if let context = context {
            userMessage += "\n\nContext around the text: \(context)"
        }

        let messages = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userMessage]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7,
            "max_tokens": 500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        throw NSError(domain: "OpenAIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
    }
}
