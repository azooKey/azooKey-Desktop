import Core
import Testing

@Test(arguments: [UInt16(48), 36, 125, 126])
func predictionSelectionKeepsExistingComposingKeyActions(_ keyCode: UInt16) {
    let event = KeyEventCore(modifierFlags: [], characters: nil, charactersIgnoringModifiers: nil, keyCode: keyCode)
    let (action, callback) = InputState.composing.event(
        eventCore: event,
        userAction: UserAction.getUserAction(eventCore: event, inputLanguage: .japanese),
        inputLanguage: .japanese,
        liveConversionEnabled: true,
        enableDebugWindow: false,
        enableSuggestion: false
    )
    switch (keyCode, action, callback) {
    case (48, .acceptPredictionCandidate, .fallthrough),
         (36, .commitMarkedText, .transition(.none)),
         (125, .enterCandidateSelectionMode, .transition(.selecting)),
         (126, .consume, .fallthrough):
        break
    default:
        Issue.record("Unexpected existing key action: \(action), \(callback)")
    }
}
