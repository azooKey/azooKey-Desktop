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
    public struct PredictionResponse {
        @Guide(description: "Array of prediction strings")
        public let predictions: [String]
    }

    public static func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)? = nil) async throws -> [String] {
        #if canImport(FoundationModels)
        logger?("Foundation Models request started")

        let systemModel = SystemLanguageModel.default

        guard case .available = systemModel.availability else {
            logger?("Foundation Models not available")
            throw OpenAIError.invalidURL
        }

        let session = try LanguageModelSession(model: systemModel)

        // Build prompt from request
        let promptText = """
        \(Prompt.dictionary[request.target] ?? Prompt.dictionary[""]!)

        Input: \(request.target)
        Output:
        """

        logger?("Sending prompt to Foundation Models: \(promptText)")

        do {
            let response = try await session.respond(to: promptText)

            // Parse response
            logger?("Foundation Models response received: \(response.content)")

            // Try to parse as JSON array
            if let data = response.content.data(using: .utf8),
               let predictions = try? JSONDecoder().decode([String].self, from: data) {
                return predictions
            }

            // Fallback: return as single prediction
            return [response.content]
        } catch {
            logger?("Foundation Models error: \(error.localizedDescription)")
            throw OpenAIError.parseError("Generation failed: \(error.localizedDescription)")
        }
        #else
        throw OpenAIError.invalidRequest
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
