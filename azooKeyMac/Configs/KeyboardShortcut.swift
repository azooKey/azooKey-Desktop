import Cocoa

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

/// NSEvent.ModifierFlagsをCodable/Sendableにするためのラッパー
public struct EventModifierFlags: Codable, Equatable, Hashable, Sendable {
    private var rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public init(from nsModifiers: NSEvent.ModifierFlags) {
        self.rawValue = nsModifiers.rawValue
    }

    public var nsModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: rawValue)
    }

    public static let control = EventModifierFlags(from: .control)
    public static let option = EventModifierFlags(from: .option)
    public static let shift = EventModifierFlags(from: .shift)
    public static let command = EventModifierFlags(from: .command)

    public func contains(_ other: EventModifierFlags) -> Bool {
        (rawValue & other.rawValue) == other.rawValue
    }
}
