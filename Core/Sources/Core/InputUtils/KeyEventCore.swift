public struct KeyEventCore: Sendable, Equatable {
    public struct ModifierFlag: OptionSet, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let shift   = ModifierFlag(rawValue: 1 << 0)
        public static let control = ModifierFlag(rawValue: 1 << 1)
        public static let option  = ModifierFlag(rawValue: 1 << 2)
        public static let command = ModifierFlag(rawValue: 1 << 3)
    }

    public init(modifierFlags: ModifierFlag, characters: String?, charactersIgnoringModifiers: String?, keyCode: UInt16) {
        self.modifierFlags = modifierFlags
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.keyCode = keyCode
    }
    var modifierFlags: ModifierFlag
    var characters: String?
    var charactersIgnoringModifiers: String?
    var keyCode: UInt16
}
