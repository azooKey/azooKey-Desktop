import Core
import Foundation
import KanaKanjiConverterModule
import Testing

private let spaceEvent = KeyEventCore(
    modifierFlags: [],
    characters: " ",
    charactersIgnoringModifiers: " ",
    keyCode: 49
)

@Suite("InputState space key behavior in composing state")
struct InputStateSpaceTests {
    @Test func spaceInEnglishComposingAppendsSpace() {
        let (action, _) = InputState.composing.event(
            eventCore: spaceEvent,
            userAction: .space(prefersFullWidthWhenInput: false),
            inputLanguage: .english,
            liveConversionEnabled: false,
            enableDebugWindow: false,
            enableSuggestion: false
        )
        guard case .appendToMarkedText(let text) = action else {
            Issue.record("Expected appendToMarkedText, got \(action)")
            return
        }
        #expect(text == " ")
    }

    @Test func spaceInEnglishComposingAppendsSpaceEvenWithLiveConversion() {
        let (action, _) = InputState.composing.event(
            eventCore: spaceEvent,
            userAction: .space(prefersFullWidthWhenInput: false),
            inputLanguage: .english,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false
        )
        guard case .appendToMarkedText(let text) = action else {
            Issue.record("Expected appendToMarkedText, got \(action)")
            return
        }
        #expect(text == " ")
    }

    @Test func spaceInJapaneseComposingWithLiveConversionEntersCandidateSelection() {
        let (action, callback) = InputState.composing.event(
            eventCore: spaceEvent,
            userAction: .space(prefersFullWidthWhenInput: false),
            inputLanguage: .japanese,
            liveConversionEnabled: true,
            enableDebugWindow: false,
            enableSuggestion: false
        )
        guard case .enterCandidateSelectionMode = action else {
            Issue.record("Expected enterCandidateSelectionMode, got \(action)")
            return
        }
        guard case .transition(.selecting) = callback else {
            Issue.record("Expected transition(.selecting), got \(callback)")
            return
        }
    }

    @Test func spaceInJapaneseComposingWithoutLiveConversionEntersPreview() {
        let (action, callback) = InputState.composing.event(
            eventCore: spaceEvent,
            userAction: .space(prefersFullWidthWhenInput: false),
            inputLanguage: .japanese,
            liveConversionEnabled: false,
            enableDebugWindow: false,
            enableSuggestion: false
        )
        guard case .enterFirstCandidatePreviewMode = action else {
            Issue.record("Expected enterFirstCandidatePreviewMode, got \(action)")
            return
        }
        guard case .transition(.previewing) = callback else {
            Issue.record("Expected transition(.previewing), got \(callback)")
            return
        }
    }
}
