import Foundation

// AI Backend selection
public enum AIBackend: String, Codable, CaseIterable, Sendable {
    case foundationModels = "Foundation Models"
    case openAI = "OpenAI API"

    public static var `default`: AIBackend {
        if #available(macOS 26.0, *) {
            let availability = FoundationModelsClientCompat.checkAvailability()
            if availability.isAvailable {
                return .foundationModels
            }
        }
        return .openAI
    }
}

public struct AIPredictionRequest: Sendable {
    public init(prompt: String, target: String, modelName: String) {
        self.prompt = prompt
        self.target = target
        self.modelName = modelName
    }

    let prompt: String
    let target: String
    let modelName: String
}

public typealias OpenAIRequest = AIPredictionRequest

public struct AITextTransformRequest: Sendable {
    public init(prompt: String, modelName: String) {
        self.prompt = prompt
        self.modelName = modelName
    }

    let prompt: String
    let modelName: String
}

// Unified AI Client that routes to the appropriate backend
public enum AIClient {
    public enum Configuration: Sendable {
        case foundationModels
        case openAI(apiKey: String, apiEndpoint: String)
    }

    public static func configuration(
        for backend: AIBackend,
        apiKey: String = "",
        apiEndpoint: String = ""
    ) -> Configuration {
        switch backend {
        case .foundationModels:
            return .foundationModels
        case .openAI:
            return .openAI(apiKey: apiKey, apiEndpoint: apiEndpoint)
        }
    }

    public static func sendPrediction(
        _ request: AIPredictionRequest,
        using configuration: Configuration,
        logger: ((String) -> Void)? = nil
    ) async throws -> [String] {
        switch configuration {
        case .foundationModels:
            return try await FoundationModelsClientCompat.sendRequest(request, logger: logger)
        case .openAI(let apiKey, let apiEndpoint):
            return try await OpenAIClient.sendRequest(request, apiKey: apiKey, apiEndpoint: apiEndpoint, logger: logger)
        }
    }

    public static func sendTextTransform(
        _ request: AITextTransformRequest,
        using configuration: Configuration,
        logger: ((String) -> Void)? = nil
    ) async throws -> String {
        switch configuration {
        case .foundationModels:
            return try await FoundationModelsClientCompat.sendTextTransformRequest(request.prompt, logger: logger)
        case .openAI(let apiKey, let apiEndpoint):
            return try await OpenAIClient.sendTextTransformRequest(
                request,
                apiKey: apiKey,
                apiEndpoint: apiEndpoint,
                logger: logger
            )
        }
    }

    public static func sendRequest(
        _ request: AIPredictionRequest,
        backend: AIBackend,
        apiKey: String = "",
        apiEndpoint: String = "",
        logger: ((String) -> Void)? = nil
    ) async throws -> [String] {
        try await sendPrediction(
            request,
            using: configuration(for: backend, apiKey: apiKey, apiEndpoint: apiEndpoint),
            logger: logger
        )
    }

    public static func sendTextTransformRequest(
        _ prompt: String,
        backend: AIBackend,
        modelName: String = "",
        apiKey: String = "",
        apiEndpoint: String = "",
        logger: ((String) -> Void)? = nil
    ) async throws -> String {
        try await sendTextTransform(
            .init(prompt: prompt, modelName: modelName),
            using: configuration(for: backend, apiKey: apiKey, apiEndpoint: apiEndpoint),
            logger: logger
        )
    }
}
