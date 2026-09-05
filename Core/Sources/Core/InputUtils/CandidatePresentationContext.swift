import KanaKanjiConverterModuleWithDefaultDictionary

public struct CandidatePresentationContext: Sendable {
    public var annotationText: String?
    public var extraValues: [String: String]

    public init(annotationText: String? = nil, extraValues: [String: String] = [:]) {
        self.annotationText = annotationText
        self.extraValues = extraValues
    }
}

public struct CandidatePresentation: Sendable {
    public var candidate: Candidate
    public var displayContext: CandidatePresentationContext

    public init(candidate: Candidate, displayContext: CandidatePresentationContext = .init()) {
        self.candidate = candidate
        self.displayContext = displayContext
        if self.displayContext.annotationText == nil {
            self.displayContext.annotationText = Self.symbolAnnotation(for: candidate.text)
        }
    }

    private static func symbolAnnotation(for text: String) -> String? {
        switch text {
        case "-": "半角ハイフン"
        case "－": "全角ハイフン"
        case "ｰ": "半角長音符"
        case "ー": "全角長音符"
        case "−": "マイナス記号"
        default: nil
        }
    }
}
