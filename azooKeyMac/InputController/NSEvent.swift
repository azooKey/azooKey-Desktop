import Cocoa
import Core

extension NSEvent {
    var keyEventCore: KeyEventCore {
        var modifierFlags: [KeyEventCore.ModifierFlag] = []
        if self.modifierFlags.contains(.shift) {
            modifierFlags.append(.shift)
        }
        if self.modifierFlags.contains(.control) {
            modifierFlags.append(.control)
        }
        if self.modifierFlags.contains(.command) {
            modifierFlags.append(.command)
        }
        if self.modifierFlags.contains(.option) {
            modifierFlags.append(.option)
        }
        return KeyEventCore(
            modifierFlags: modifierFlags,
            characters: self.characters,
            charactersIgnoringModifiers: self.charactersIgnoringModifiers,
            keyCode: self.keyCode
        )
    }
}
