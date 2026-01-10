public struct KeyEventCore: Sendable, Equatable {
    public enum ModifierFlag: Sendable, Equatable, Hashable {
        case option
        case control
        case command
        case shift
    }

    public init(modifierFlags: [ModifierFlag], characters: String?, charactersIgnoringModifiers: String?, keyCode: UInt16) {
        self.modifierFlags = modifierFlags
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.keyCode = keyCode
    }
    var modifierFlags: [ModifierFlag]
    var characters: String?
    var charactersIgnoringModifiers: String?
    var keyCode: UInt16
}
