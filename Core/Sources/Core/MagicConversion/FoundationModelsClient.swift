import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

// Foundation Models availability checker
public enum FoundationModelsAvailability {
    case available
    case unavailable(reason: UnavailabilityReason)

    public enum UnavailabilityReason {
        case osVersionTooOld
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case frameworkNotAvailable
    }

    public var isAvailable: Bool {
        if case .available = self {
            return true
        }
        return false
    }
}

// Foundation Models Client for macOS 26.0+
@available(macOS 26.0, *)
public enum FoundationModelsClient {

    // Check if Foundation Models is available on this system
    public static func checkAvailability() -> FoundationModelsAvailability {
        #if canImport(FoundationModels)
        let systemModel = SystemLanguageModel.default

        switch systemModel.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(reason: .deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(reason: .appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(reason: .modelNotReady)
            @unknown default:
                return .unavailable(reason: .deviceNotEligible)
            }
        @unknown default:
            return .unavailable(reason: .deviceNotEligible)
        }
        #else
        return .unavailable(reason: .frameworkNotAvailable)
        #endif
    }

    @Generable
    public struct PredictionResponse: Codable {
        @Guide(description: "Array of prediction strings", .count(3...5))
        public var predictions: [String]
    }

    public static func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)? = nil) async throws -> [String] {
        #if canImport(FoundationModels)
        logger?("Foundation Models request started")

        let systemModel = SystemLanguageModel.default

        guard case .available = systemModel.availability else {
            logger?("Foundation Models not available")
            throw OpenAIError.invalidURL
        }

        let session = LanguageModelSession(model: systemModel)

        // Build prompt - simplified since we use @Generable for structured output
        let promptText = """
        \(Prompt.getPromptText(for: request.target))

        Input: `\(request.prompt)<\(request.target)>`
        """

        logger?("Requesting from Foundation Models with guided generation")

        // Use guided generation with @Generable to get structured output directly
        let response = try await session.respond(to: promptText, generating: PredictionResponse.self)

        logger?("Received structured response with \(response.content.predictions.count) predictions")
        return response.content.predictions
        #else
        throw OpenAIError.invalidURL
        #endif
    }
}

// Compatibility wrapper for older macOS versions
public enum FoundationModelsClientCompat {
    public static func checkAvailability() -> FoundationModelsAvailability {
        if #available(macOS 26.0, *) {
            return FoundationModelsClient.checkAvailability()
        } else {
            return .unavailable(reason: .osVersionTooOld)
        }
    }

    public static func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)? = nil) async throws -> [String] {
        if #available(macOS 26.0, *) {
            return try await FoundationModelsClient.sendRequest(request, logger: logger)
        } else {
            throw OpenAIError.parseError("Foundation Models requires macOS 26.0 or later")
        }
    }
}
