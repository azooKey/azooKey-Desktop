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

// Foundation Models specific errors
public enum FoundationModelsError: LocalizedError, @unchecked Sendable {
    case unavailable(FoundationModelsAvailability.UnavailabilityReason)
    case responseParsingFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason):
            switch reason {
            case .osVersionTooOld:
                return "Foundation Models requires macOS 26.0 or later"
            case .deviceNotEligible:
                return "Foundation Models is not available on this device"
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is not enabled"
            case .modelNotReady:
                return "Foundation Models is not ready"
            case .frameworkNotAvailable:
                return "Foundation Models framework is not available"
            }
        case .responseParsingFailed:
            return "Failed to parse Foundation Models response"
        }
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

    #if canImport(FoundationModels)
    @Generable
    public struct PredictionResponse: Codable {
        @Guide(description: "Array of prediction strings", .count(3...5))
        public var predictions: [String]
    }

    @Generable
    public struct TextTransformResponse: Codable {
        @Guide(description: "The transformed text")
        public var result: String
    }
    #endif

    public static func sendRequest(_ request: OpenAIRequest, logger: ((String) -> Void)? = nil) async throws -> [String] {
        #if canImport(FoundationModels)
        logger?("Foundation Models request started")

        let systemModel = SystemLanguageModel.default

        // Check availability and throw appropriate error
        switch systemModel.availability {
        case .available:
            break
        case .unavailable(let reason):
            logger?("Foundation Models not available: \(reason)")
            let mappedReason: FoundationModelsAvailability.UnavailabilityReason = switch reason {
            case .deviceNotEligible:
                .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                .appleIntelligenceNotEnabled
            case .modelNotReady:
                .modelNotReady
            @unknown default:
                .deviceNotEligible
            }
            throw FoundationModelsError.unavailable(mappedReason)
        @unknown default:
            logger?("Foundation Models availability unknown")
            throw FoundationModelsError.unavailable(.deviceNotEligible)
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
        throw FoundationModelsError.unavailable(.frameworkNotAvailable)
        #endif
    }

    public static func sendTextTransformRequest(_ prompt: String, logger: ((String) -> Void)? = nil) async throws -> String {
        #if canImport(FoundationModels)
        logger?("Foundation Models text transform request started")

        let systemModel = SystemLanguageModel.default

        switch systemModel.availability {
        case .available:
            break
        case .unavailable(let reason):
            logger?("Foundation Models not available: \(reason)")
            let mappedReason: FoundationModelsAvailability.UnavailabilityReason = switch reason {
            case .deviceNotEligible:
                .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                .appleIntelligenceNotEnabled
            case .modelNotReady:
                .modelNotReady
            @unknown default:
                .deviceNotEligible
            }
            throw FoundationModelsError.unavailable(mappedReason)
        @unknown default:
            logger?("Foundation Models availability unknown")
            throw FoundationModelsError.unavailable(.deviceNotEligible)
        }

        let session = LanguageModelSession(model: systemModel)
        let response = try await session.respond(to: prompt, generating: TextTransformResponse.self)

        logger?("Received structured response for text transform")
        return response.content.result.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        throw FoundationModelsError.unavailable(.frameworkNotAvailable)
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
            throw FoundationModelsError.unavailable(.osVersionTooOld)
        }
    }

    public static func sendTextTransformRequest(_ prompt: String, logger: ((String) -> Void)? = nil) async throws -> String {
        if #available(macOS 26.0, *) {
            return try await FoundationModelsClient.sendTextTransformRequest(prompt, logger: logger)
        } else {
            throw FoundationModelsError.unavailable(.osVersionTooOld)
        }
    }
}
