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

protocol StringConfigItemWithDefault: ConfigItem<String> {
    static var `default`: String { get }
}

extension StringConfigItemWithDefault {
    public var value: String {
        get {
            let stored = UserDefaults.standard.string(forKey: Self.key) ?? ""
            return stored.isEmpty ? Self.default : stored
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: Self.key)
        }
    }
}

extension Config {
    /// 英数キーダブルタップのプロンプト
    public struct EisuDoubleTapPrompt: StringConfigItemWithDefault {
        public init() {}

        public static let `default`: String = "english"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.eisu_double_tap_prompt"
    }

    /// かなキーダブルタップのプロンプト
    public struct KanaDoubleTapPrompt: StringConfigItemWithDefault {
        public init() {}

        public static let `default`: String = "japanese"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.kana_double_tap_prompt"
    }
}
