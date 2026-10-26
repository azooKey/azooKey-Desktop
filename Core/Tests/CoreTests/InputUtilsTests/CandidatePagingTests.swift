import Core
import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

@Test(arguments: [UInt16(0x74), 0x79], [InputState.none, .composing, .previewing, .selecting, .replaceSuggestion])
func pageKeysOnlyNavigateCandidatesDuringSelection(_ keyCode: UInt16, _ state: InputState) {
    let event = KeyEventCore(modifierFlags: [], characters: nil, charactersIgnoringModifiers: nil, keyCode: keyCode)
    let (action, callback) = state.event(
        eventCore: event,
        userAction: UserAction.getUserAction(eventCore: event, inputLanguage: .japanese),
        inputLanguage: .japanese,
        liveConversionEnabled: true,
        enableDebugWindow: false,
        enableSuggestion: false
    )
    switch (state, action, callback) {
    case (.selecting, .selectCandidatePage(let count), .fallthrough):
        #expect(count == (keyCode == 0x74 ? -1 : 1))
    case (.none, .fallthrough, .fallthrough),
         (.composing, .fallthrough, .fallthrough),
         (.previewing, .fallthrough, .fallthrough),
         (.replaceSuggestion, .fallthrough, .fallthrough):
        break
    default:
        Issue.record("Unexpected page key behavior in \(state): \(action), \(callback)")
    }
}

@MainActor
@Test func selectingAdditionalCandidatesShowsAllCharacterStyles() {
    let manager = SegmentsManager(
        kanaKanjiConverter: .withDefaultDictionary(),
        applicationDirectoryURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
        containerURL: nil,
        context: .init(useZenzai: false)
    )
    manager.insertAtCursorPosition("abc", inputStyle: .direct)
    manager.requestSetCandidateWindowState(visible: true)
    manager.requestSelectingAdditionalCandidates()

    guard case .selecting(let candidates, let selectionIndex) = manager.getCurrentCandidateWindow(inputState: .selecting) else {
        Issue.record("Expected character style candidates to be visible.")
        return
    }
    let annotationTexts = manager.makeCandidatePresentations(candidates)
        .compactMap { $0.displayContext.annotationText }
    #expect(annotationTexts == ["英数", "全角英数", "半角カナ", "カタカナ", "ひらがな"])
    #expect(selectionIndex == 0)
}
