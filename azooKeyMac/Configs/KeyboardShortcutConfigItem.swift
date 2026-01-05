//
//  KeyboardShortcutConfigItem.swift
//  azooKeyMac
//
//  Created by Claude Code
//

@_spi(Core) import Core
import Foundation

protocol KeyboardShortcutConfigItem: ConfigItem<KeyboardShortcut> {
    static var `default`: KeyboardShortcut { get }
}

extension KeyboardShortcutConfigItem {
    public var value: KeyboardShortcut {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.key) else {
                return Self.default
            }
            do {
                let decoded = try JSONDecoder().decode(KeyboardShortcut.self, from: data)
                return decoded
            } catch {
                print(#file, #line, error)
                return Self.default
            }
        }
        nonmutating set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encoded, forKey: Self.key)
            } catch {
                print(#file, #line, error)
            }
        }
    }
}

extension Config {
    /// いい感じ変換のキーボードショートカット
    public struct TransformShortcut: KeyboardShortcutConfigItem {
        public init() {}

        public static let `default`: KeyboardShortcut = .defaultTransformShortcut
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.transform_shortcut"
    }
}

protocol CustomPromptShortcutsConfigItem: ConfigItem<[CustomPromptShortcut]> {
    static var `default`: [CustomPromptShortcut] { get }
}

extension CustomPromptShortcutsConfigItem {
    public var value: [CustomPromptShortcut] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.key) else {
                return Self.default
            }
            do {
                let decoded = try JSONDecoder().decode([CustomPromptShortcut].self, from: data)
                return decoded
            } catch {
                print(#file, #line, error)
                return Self.default
            }
        }
        nonmutating set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encoded, forKey: Self.key)
            } catch {
                print(#file, #line, error)
            }
        }
    }
}

extension Config {
    /// カスタムプロンプトショートカットのリスト
    public struct CustomPromptShortcuts: CustomPromptShortcutsConfigItem {
        public init() {}

        public static let `default`: [CustomPromptShortcut] = []
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.custom_prompt_shortcuts"
    }
}
