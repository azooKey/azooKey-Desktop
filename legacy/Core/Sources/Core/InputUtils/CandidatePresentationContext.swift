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
    }
}
