import Cocoa
import Core

extension NSEvent {
    var keyEventCore: KeyEventCore {
        var modifierFlags: KeyEventCore.ModifierFlag = []
        if self.modifierFlags.contains(.shift) {
            modifierFlags.insert(.shift)
        }
        if self.modifierFlags.contains(.control) {
            modifierFlags.insert(.control)
        }
        if self.modifierFlags.contains(.command) {
            modifierFlags.insert(.command)
        }
        if self.modifierFlags.contains(.option) {
            modifierFlags.insert(.option)
        }
        return KeyEventCore(
            modifierFlags: modifierFlags,
            characters: self.characters,
            charactersIgnoringModifiers: self.charactersIgnoringModifiers,
            keyCode: self.keyCode
        )
    }
}
