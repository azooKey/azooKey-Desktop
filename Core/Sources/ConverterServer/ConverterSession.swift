import Core
import KanaKanjiConverterModuleWithDefaultDictionary

final class ConverterSession: SegmentManagerDelegate {
    let manager: SegmentsManager
    private var leftSideContext: String?
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

    func setLeftSideContext(_ value: String?) {
        self.leftSideContext = value
    }

    func getLeftSideContext(maxCount: Int) -> String? {
        guard let leftSideContext else {
            return nil
        }
        return String(leftSideContext.suffix(maxCount))
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
