//
//  LearningConfig.swift
//  azooKeyMac
//
//  Created by miwa on 2024/04/27.
//

import Foundation
import struct KanaKanjiConverterModuleWithDefaultDictionary.ConvertRequestOptions
import enum KanaKanjiConverterModuleWithDefaultDictionary.LearningType

protocol CustomCodableConfigItem: ConfigItem {
    static var `default`: Value { get }
}

extension CustomCodableConfigItem {
    public var value: Value {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.key) else {
                print(#file, #line, "data is not set yet")
                return Self.default
            }
            do {
                let decoded = try JSONDecoder().decode(Value.self, from: data)
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
    /// ライブ変換を有効化する設定
    public struct Learning: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case inputAndOutput
            case onlyOutput
            case nothing

            public var learningType: LearningType {
                switch self {
                case .inputAndOutput:
                    .inputAndOutput
                case .onlyOutput:
                    .onlyOutput
                case .nothing:
                    .nothing
                }
            }
        }

        public init() {}
        static let `default`: Value = .inputAndOutput
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.learning"
    }
}

extension Config {
    public struct UserDictionaryEntry: Sendable, Codable, Identifiable {
        public init(word: String, reading: String, hint: String? = nil) {
            self.id = UUID()
            self.word = word
            self.reading = reading
            self.hint = hint
        }

        public var id: UUID
        public var word: String
        public var reading: String
        var hint: String?

        public var nonNullHint: String {
            get {
                hint ?? ""
            }
            set {
                if newValue.isEmpty {
                    hint = nil
                } else {
                    hint = newValue
                }
            }
        }
    }

    public struct UserDictionary: CustomCodableConfigItem {
        public struct Value: Codable, Sendable {
            public var items: [UserDictionaryEntry]
        }

        public var items: Value = Self.default

        public init(items: Value = Self.default) {
            self.items = items
        }

        public static let `default`: Value = .init(items: [
            .init(word: "azooKey", reading: "あずーきー", hint: "アプリ")
        ])
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.user_dictionary_temporal2"
    }

    public struct SystemUserDictionary: CustomCodableConfigItem {
        public struct Value: Codable, Sendable {
            public var lastUpdate: Date?
            public var items: [UserDictionaryEntry]
        }

        public var items: Value = Self.default

        public init(items: Value = Self.default) {
            self.items = items
        }

        public static let `default`: Value = .init(items: [])
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.system_user_dictionary"
    }
}

extension Config {
    /// Zenzaiのパーソナライズ強度
    public struct ZenzaiPersonalizationLevel: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case off
            case soft
            case normal
            case hard

            public var alpha: Float {
                switch self {
                case .off:
                    0
                case .soft:
                    0.5
                case .normal:
                    1.0
                case .hard:
                    1.5
                }
            }
        }

        public init() {}
        public static let `default`: Value = .normal
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.zenzai.personalization_level"
    }
}

extension Config {
    public struct KeyBindings: CustomCodableConfigItem {
        public enum KeyBindingAction: String, Codable, Sendable, Equatable, Hashable {
            case backspace
            case enter
            case navigationUp
            case navigationDown
            case navigationRight
            case navigationLeft
            case editSegmentLeft
            case editSegmentRight
            case functionSix
            case functionSeven
            case functionEight
            case functionNine
            case functionTen
            case suggest
            case startUnicodeInput

            public func toUserAction() -> UserAction? {
                switch self {
                case .backspace:
                    return .backspace
                case .enter:
                    return .enter
                case .navigationUp:
                    return .navigation(.up)
                case .navigationDown:
                    return .navigation(.down)
                case .navigationRight:
                    return .navigation(.right)
                case .navigationLeft:
                    return .navigation(.left)
                case .editSegmentLeft:
                    return .editSegment(-1)
                case .editSegmentRight:
                    return .editSegment(1)
                case .functionSix:
                    return .function(.six)
                case .functionSeven:
                    return .function(.seven)
                case .functionEight:
                    return .function(.eight)
                case .functionNine:
                    return .function(.nine)
                case .functionTen:
                    return .function(.ten)
                case .suggest:
                    return .suggest
                case .startUnicodeInput:
                    return .startUnicodeInput
                }
            }
        }

        public enum Modifier: String, Codable, Sendable, Equatable, Hashable {
            case control
            case shift
            case option
            case command

            public func toModifierFlag() -> KeyEventCore.ModifierFlag {
                switch self {
                case .control: return .control
                case .shift: return .shift
                case .option: return .option
                case .command: return .command
                }
            }

            public static func modifierFlagsFromArray(_ modifiers: [Modifier]) -> KeyEventCore.ModifierFlag {
                modifiers.reduce(into: KeyEventCore.ModifierFlag()) { result, modifier in
                    result.insert(modifier.toModifierFlag())
                }
            }
        }

        public struct KeyBinding: Codable, Sendable, Equatable, Hashable {
            public var key: String
            public var modifiers: [Modifier]
            public var action: KeyBindingAction

            public init(key: String, modifiers: [Modifier], action: KeyBindingAction) {
                self.key = key
                self.modifiers = modifiers
                self.action = action
            }
        }

        public struct Value: Codable, Sendable, Equatable {
            public var bindings: [KeyBinding]

            public init(bindings: [KeyBinding]) {
                self.bindings = bindings
            }
        }

        public init() {}

        public static let `default`: Value = .init(bindings: [
            .init(key: "h", modifiers: [.control], action: .backspace),
            .init(key: "p", modifiers: [.control], action: .navigationUp),
            .init(key: "m", modifiers: [.control], action: .enter),
            .init(key: "n", modifiers: [.control], action: .navigationDown),
            .init(key: "f", modifiers: [.control], action: .navigationRight),
            .init(key: "i", modifiers: [.control], action: .editSegmentLeft),
            .init(key: "o", modifiers: [.control], action: .editSegmentRight),
            .init(key: "l", modifiers: [.control], action: .functionNine),
            .init(key: "j", modifiers: [.control], action: .functionSix),
            .init(key: "k", modifiers: [.control], action: .functionSeven),
            .init(key: ";", modifiers: [.control], action: .functionEight),
            .init(key: ":", modifiers: [.control], action: .functionTen),
            .init(key: "'", modifiers: [.control], action: .functionTen),
            .init(key: "s", modifiers: [.control], action: .suggest),
            .init(key: "u", modifiers: [.control, .shift], action: .startUnicodeInput)
        ])

        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.key_bindings"

        public func findAction(key: String, modifierFlags: KeyEventCore.ModifierFlag) -> KeyBindingAction? {
            let bindings = self.value.bindings
            for binding in bindings {
                let bindingModifiers = Modifier.modifierFlagsFromArray(binding.modifiers)
                if binding.key.lowercased() == key.lowercased() && bindingModifiers == modifierFlags {
                    return binding.action
                }
            }
            return nil
        }
    }
}

extension Config {
    public struct InputStyle: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case `default`
            case defaultAZIK
            case defaultKanaJIS
            case defaultKanaUS
            case custom
        }

        public init() {}
        public static let `default`: Value = .default
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.input_style"
    }
}

extension Config {
    /// キーボードレイアウトの設定
    public struct KeyboardLayout: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case qwerty
            case australian
            case colemak
            case dvorak
            case dvorakQwertyCommand

            public var layoutIdentifier: String {
                switch self {
                case .qwerty:
                    return "com.apple.keylayout.US"
                case .australian:
                    return "com.apple.keylayout.Australian"
                case .colemak:
                    return "com.apple.keylayout.Colemak"
                case .dvorak:
                    return "com.apple.keylayout.Dvorak"
                case .dvorakQwertyCommand:
                    return "com.apple.keylayout.DVORAK-QWERTYCMD"
                }
            }
        }

        public init() {}
        public static let `default`: Value = .qwerty
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.keyboard_layout"
    }

    public struct AIBackendPreference: CustomCodableConfigItem {
        public enum Value: String, Codable, Equatable, Hashable, Sendable {
            case off = "Off"
            case foundationModels = "Foundation Models"
            case openAI = "OpenAI API"
        }

        public init() {}

        public static var `default`: Value {
            // Migration: If user had OpenAI API enabled, preserve that setting
            let legacyKey = Config.Deprecated.EnableOpenAiApiKey.key
            if let legacyValue = UserDefaults.standard.object(forKey: legacyKey) as? Bool,
               legacyValue {
                return .openAI
            }
            return .off
        }
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.aiBackend"
    }
}
