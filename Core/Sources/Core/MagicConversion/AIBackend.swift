import Foundation

// AI Backend selection
public enum AIBackend: String, Codable, CaseIterable {
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

// Unified AI Client that routes to the appropriate backend
public enum AIClient {
    public static func sendRequest(
        _ request: OpenAIRequest,
        backend: AIBackend,
        apiKey: String = "",
        apiEndpoint: String = "",
        logger: ((String) -> Void)? = nil
    ) async throws -> [String] {
        switch backend {
        case .foundationModels:
            return try await FoundationModelsClientCompat.sendRequest(request, logger: logger)
        case .openAI:
            return try await OpenAIClient.sendRequest(request, apiKey: apiKey, apiEndpoint: apiEndpoint, logger: logger)
        }
    }
}
