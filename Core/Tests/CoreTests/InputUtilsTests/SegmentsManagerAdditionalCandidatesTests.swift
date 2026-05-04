@testable import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

private func makeSegmentsManager() -> SegmentsManager {
    SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
}

@MainActor
private func makeEditedRangeScenario() -> (manager: SegmentsManager, selectedRuby: String) {
    let manager = makeSegmentsManager()
    manager.insertAtCursorPosition("hennkann", inputStyle: .roman2kana)
    manager.editSegment(count: -1)
    manager.requestSetCandidateWindowState(visible: true)
    _ = manager.getCurrentCandidateWindow(inputState: .selecting)

    let selectedRuby = manager.selectedCandidate!.data.map(\.ruby).joined()
    return (manager, selectedRuby)
}

@MainActor
@Test func testAdditionalHiraganaCandidateUsesEditedSelectionRuby() async throws {
    let (manager, selectedRuby) = makeEditedRangeScenario()
    manager.requestSelectingPrevCandidate()

    switch manager.getCurrentCandidateWindow(inputState: .selecting) {
    case .selecting(let candidates, _):
        let presentations = manager.makeCandidatePresentations(candidates)
        guard let hiraganaPresentation = presentations.first(where: { $0.displayContext.annotationText == "ひらがな" }) else {
            Issue.record("Expected additional hiragana candidate.")
            return
        }
        let hiraganaRuby = hiraganaPresentation.candidate.data.map(\.ruby).joined()
        #expect(hiraganaRuby == selectedRuby)
    case .hidden, .composing:
        Issue.record("Expected selecting state while showing additional candidates.")
    }
}

@MainActor
@Test func testAdditionalCandidatesExpandInSuffixOrder() async throws {
    let manager = makeSegmentsManager()
    manager.insertAtCursorPosition("abc", inputStyle: .direct)
    manager.requestSetCandidateWindowState(visible: true)

    manager.requestSelectingPrevCandidate()

    switch manager.getCurrentCandidateWindow(inputState: .selecting) {
    case .selecting(let candidates, let selectionIndex):
        #expect(selectionIndex == 0)
        let firstContexts = manager.makeCandidatePresentations(candidates).map(\.displayContext)
        #expect(firstContexts.count == candidates.count)
        #expect(firstContexts.first?.annotationText == "ひらがな")
    case .hidden, .composing:
        Issue.record("Expected selecting state after first previous-selection request.")
        return
    }

    manager.requestSelectingPrevCandidate()

    switch manager.getCurrentCandidateWindow(inputState: .selecting) {
    case .selecting(let candidates, let selectionIndex):
        #expect(selectionIndex == 0)
        let contexts = manager.makeCandidatePresentations(candidates).map(\.displayContext)
        if contexts.count >= 2 {
            #expect(contexts[0].annotationText == "カタカナ")
            #expect(contexts[1].annotationText == "ひらがな")
        } else {
            Issue.record("Expected at least 2 additional candidates after second request.")
        }
    case .hidden, .composing:
        Issue.record("Expected selecting state after second previous-selection request.")
    }
}

@MainActor
@Test func testAdditionalCandidatesExpansionCapsAtDeclaredCount() async throws {
    let manager = makeSegmentsManager()
    manager.insertAtCursorPosition("abc", inputStyle: .direct)
    manager.requestSetCandidateWindowState(visible: true)

    for _ in 0..<10 {
        manager.requestSelectingPrevCandidate()
    }

    switch manager.getCurrentCandidateWindow(inputState: .selecting) {
    case .selecting(let candidates, _):
        let annotationTexts = manager.makeCandidatePresentations(candidates)
            .map(\.displayContext)
            .compactMap(\.annotationText)
        #expect(annotationTexts == ["英数", "全角英数", "半角カナ", "カタカナ", "ひらがな"])
    case .hidden, .composing:
        Issue.record("Expected selecting state while additional candidates are expanded.")
    }
}

@MainActor
@Test func testResettingSelectionClearsAdditionalCandidateContexts() async throws {
    let manager = makeSegmentsManager()
    manager.insertAtCursorPosition("abc", inputStyle: .direct)
    manager.requestSetCandidateWindowState(visible: true)
    manager.requestSelectingPrevCandidate()

    switch manager.getCurrentCandidateWindow(inputState: .selecting) {
    case .selecting(let candidates, _):
        let beforeReset = manager.makeCandidatePresentations(candidates).map(\.displayContext)
        #expect(beforeReset.contains { $0.annotationText != nil })

        manager.requestResettingSelection()

        let afterReset = manager.makeCandidatePresentations(candidates).map(\.displayContext)
        #expect(afterReset.allSatisfy { $0.annotationText == nil })
    case .hidden, .composing:
        Issue.record("Expected selecting state after expanding additional candidates.")
    }
}

@MainActor
@Test func userDictionaryAnnotationRequiresDisplayedCandidateTextToMatchEntryWord() async throws {
    let defaults = UserDefaults.standard
    let key = Config.UserDictionary.key
    let revisionKey = Config.UserDictionary.revisionKey
    let oldData = defaults.data(forKey: key)
    let oldRevision = defaults.object(forKey: revisionKey)
    defer {
        if let oldData {
            defaults.set(oldData, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
        if let oldRevision {
            defaults.set(oldRevision, forKey: revisionKey)
        } else {
            defaults.removeObject(forKey: revisionKey)
        }
    }

    defaults.removeObject(forKey: key)
    defaults.removeObject(forKey: revisionKey)
    Config.UserDictionary().value = .init(dictionaries: [
        .init(
            name: "数学",
            items: [
                .init(word: "Gorenstein", reading: "ごれんしゅたいん", hint: "Gorenstein 環などで知られる数学者")
            ]
        )
    ])

    let manager = makeSegmentsManager()
    manager.insertAtCursorPosition("ごれんしゅたいん", inputStyle: .direct)
    manager.update(requestRichCandidates: false)

    let data = [
        DicdataElement(
            word: "Gorenstein",
            ruby: "ゴレンシュタイン",
            cid: CIDData.固有名詞.cid,
            mid: MIDData.一般.mid,
            value: -5
        )
    ]
    let exactCandidate = Candidate(
        text: "Gorenstein",
        value: .zero,
        composingCount: .inputCount(8),
        lastMid: MIDData.一般.mid,
        data: data
    )
    let unrelatedSurfaceCandidate = Candidate(
        text: "ご恋シュタイン",
        value: .zero,
        composingCount: .inputCount(8),
        lastMid: MIDData.一般.mid,
        data: data
    )

    let presentations = manager.makeCandidatePresentations([exactCandidate, unrelatedSurfaceCandidate])
    #expect(presentations[0].displayContext.annotationText == "Gorenstein 環などで知られる数学者")
    #expect(presentations[1].displayContext.annotationText == nil)
}
