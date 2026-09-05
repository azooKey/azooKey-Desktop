import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

private func symbolCandidate(_ text: String) -> Candidate {
    Candidate(text: text, value: 0, composingCount: .surfaceCount(text.count), lastMid: 0, data: [])
}

@Test(arguments: [
    ("-", "半角ハイフン"), ("－", "全角ハイフン"), ("ｰ", "半角長音符"),
    ("ー", "全角長音符"), ("−", "マイナス記号")
])
func testSymbolCandidateAnnotation(text: String, annotation: String) throws {
    let presentation = CandidatePresentation(candidate: symbolCandidate(text))
    #expect(presentation.candidate.text == text)
    #expect(presentation.displayContext.annotationText == annotation)
    let transported = try JSONDecoder().decode(
        ConverterCandidatePresentation.self,
        from: JSONEncoder().encode(ConverterCandidatePresentation(presentation))
    )
    #expect(transported.text == text)
    #expect(transported.annotationText == annotation)
}

@Test(arguments: ["", "コーヒー", "ｰｰ", "--", " -", "ー ", "A-B", "1−2", "漢字"])
func testSymbolAnnotationRequiresEntireCandidate(text: String) {
    #expect(CandidatePresentation(candidate: symbolCandidate(text)).displayContext.annotationText == nil)
}

@Test func testSymbolAnnotationPreservesExistingContext() {
    let presentation = CandidatePresentation(
        candidate: symbolCandidate("ｰ"),
        displayContext: .init(annotationText: "半角カナ", extraValues: ["source": "additional"])
    )
    #expect(presentation.displayContext.annotationText == "半角カナ")
    #expect(presentation.displayContext.extraValues == ["source": "additional"])
}
