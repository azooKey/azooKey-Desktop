//
//  KeyboardShortcut.swift
//  azooKeyMac
//
//  Created by Claude Code
//

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

/// カスタムプロンプトとショートカットのペア
public struct CustomPromptShortcut: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var shortcut: KeyboardShortcut

    public init(id: UUID = UUID(), name: String, prompt: String, shortcut: KeyboardShortcut) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.shortcut = shortcut
    }

    /// デフォルトのカスタムプロンプトショートカット例
    public static let examples: [CustomPromptShortcut] = [
        CustomPromptShortcut(
            name: "日本語に翻訳",
            prompt: "japanese",
            shortcut: KeyboardShortcut(key: "j", modifiers: .control)
        ),
        CustomPromptShortcut(
            name: "英語に翻訳",
            prompt: "english",
            shortcut: KeyboardShortcut(key: "e", modifiers: .control)
        )
    ]
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
