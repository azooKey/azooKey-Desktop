import Foundation

class OpenAIClientAdapter: LLMClient {
    private let configuration: LLMConfiguration

    init(configuration: LLMConfiguration) {
        self.configuration = configuration
    }

    func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)?) async throws -> [String] {
        try await OpenAIClient.sendRequest(request, apiKey: configuration.apiKey, logger: logger)
    }

    func sendTextTransformRequest(prompt: String, modelName: String) async throws -> String {
        try await OpenAIClient.sendTextTransformRequest(prompt: prompt, modelName: modelName, apiKey: configuration.apiKey)
    }
}
