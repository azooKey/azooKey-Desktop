import Cocoa
import Core

extension InputState {
    public func event(  // swiftlint:disable:this function_parameter_count
        _ event: NSEvent!,
        userAction: UserAction,
        inputLanguage: InputLanguage,
        liveConversionEnabled: Bool,
        enableDebugWindow: Bool,
        enableSuggestion: Bool
    ) -> (ClientAction, ClientActionCallback) {
        var modifierFlags: [InputState.ModifierFlag] = []
        if event.modifierFlags.contains(.shift) {
            modifierFlags.append(.shift)
        }
        if event.modifierFlags.contains(.control) {
            modifierFlags.append(.control)
        }
        if event.modifierFlags.contains(.command) {
            modifierFlags.append(.command)
        }
        if event.modifierFlags.contains(.option) {
            modifierFlags.append(.option)
        }
        return self.event(
            eventCore: EventCore(modifierFlags: modifierFlags),
            userAction: userAction,
            inputLanguage: inputLanguage,
            liveConversionEnabled: liveConversionEnabled,
            enableDebugWindow: enableDebugWindow,
            enableSuggestion: enableSuggestion
        )
    }
}
