import Foundation

/// キーボードショートカットを表す構造体
public struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var modifiers: EventModifierFlags

    public init(key: String, modifiers: EventModifierFlags) {
        self.key = key
        self.modifiers = modifiers
    }

    /// デフォルトのショートカット（Control+S）
    public static let defaultTransformShortcut = KeyboardShortcut(
        key: "s",
        modifiers: .control
    )

    /// 表示用の文字列（例: "⌃S"）
    public var displayString: String {
        var result = ""

        if modifiers.contains(.control) {
            result += "⌃"
        }
        if modifiers.contains(.option) {
            result += "⌥"
        }
        if modifiers.contains(.shift) {
            result += "⇧"
        }
        if modifiers.contains(.command) {
            result += "⌘"
        }

        result += key.uppercased()
        return result
    }
}

/// ModifierFlagsをCodable/Sendableにするためのラッパー（rawValueベース）
public struct EventModifierFlags: Codable, Equatable, Hashable, Sendable {
    public var rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let control = EventModifierFlags(rawValue: 1 << 18)  // NSEvent.ModifierFlags.control.rawValue
    public static let option = EventModifierFlags(rawValue: 1 << 19)   // NSEvent.ModifierFlags.option.rawValue
    public static let shift = EventModifierFlags(rawValue: 1 << 17)    // NSEvent.ModifierFlags.shift.rawValue
    public static let command = EventModifierFlags(rawValue: 1 << 20)  // NSEvent.ModifierFlags.command.rawValue

    public func contains(_ other: EventModifierFlags) -> Bool {
        (rawValue & other.rawValue) == other.rawValue
    }
}
