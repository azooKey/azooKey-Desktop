import Core
import KanaKanjiConverterModuleWithDefaultDictionary

final class ConverterSession: SegmentManagerDelegate {
    static let conversionContextLength = 30
    static let replaceSuggestionContextLength = 100

    let manager: SegmentsManager
    private var context = ConverterTextContext()
    var config = ConverterSessionConfig(
        aiBackendPreference: .off,
        openAIModelName: Config.OpenAiModelName.default,
        openAIEndpoint: Config.OpenAiApiEndpoint.default,
        openAIAPIKey: .init(""),
        includeContextInAITransform: true
    )
    var replaceSuggestions: [Candidate] = []
    var replaceSuggestionSelectionIndex: Int?

    init(manager: SegmentsManager) {
        self.manager = manager
        self.manager.delegate = self
    }

    func setContext(_ context: ConverterTextContext) {
        self.context = context
    }

    func getLeftSideContext(maxCount: Int) -> String? {
        guard let leftSideContext = context.leftSideContext else {
            return nil
        }
        return String(leftSideContext.suffix(maxCount))
    }

    func getRightSideContext(maxCount: Int) -> String? {
        guard let rightSideContext = context.rightSideContext else {
            return nil
        }
        return String(rightSideContext.prefix(maxCount))
    }

    func conversionLeftSideContext() -> String? {
        getLeftSideContext(maxCount: Self.conversionContextLength)
    }

    func replaceSuggestionPromptContext() -> String {
        let leftSideContext = getLeftSideContext(maxCount: Self.replaceSuggestionContextLength) ?? ""
        let rightSideContext = getRightSideContext(maxCount: Self.replaceSuggestionContextLength) ?? ""
        guard !leftSideContext.isEmpty || !rightSideContext.isEmpty else {
            return ""
        }
        return [
            leftSideContext.isEmpty ? nil : "Text before: ...\(leftSideContext)",
            rightSideContext.isEmpty ? nil : "Text after: \(rightSideContext)..."
        ]
        .compactMap(\.self)
        .joined(separator: "\n")
    }

    func clearReplaceSuggestions() {
        self.replaceSuggestions = []
        self.replaceSuggestionSelectionIndex = nil
    }

    func selectReplaceSuggestion(at index: Int) {
        guard !replaceSuggestions.isEmpty else {
            replaceSuggestionSelectionIndex = nil
            return
        }
        replaceSuggestionSelectionIndex = min(max(0, index), replaceSuggestions.count - 1)
    }

    func selectNextReplaceSuggestion() {
        guard !replaceSuggestions.isEmpty else {
            replaceSuggestionSelectionIndex = nil
            return
        }
        replaceSuggestionSelectionIndex = ((replaceSuggestionSelectionIndex ?? -1) + 1) % replaceSuggestions.count
    }

    func selectPreviousReplaceSuggestion() {
        guard !replaceSuggestions.isEmpty else {
            replaceSuggestionSelectionIndex = nil
            return
        }
        let current = replaceSuggestionSelectionIndex ?? 0
        replaceSuggestionSelectionIndex = (current - 1 + replaceSuggestions.count) % replaceSuggestions.count
    }

    var selectedReplaceSuggestion: Candidate? {
        guard let replaceSuggestionSelectionIndex,
              replaceSuggestions.indices.contains(replaceSuggestionSelectionIndex) else {
            return nil
        }
        return replaceSuggestions[replaceSuggestionSelectionIndex]
    }
}
