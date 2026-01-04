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
            case colemak
            case dvorak

            public var layoutIdentifier: String {
                switch self {
                case .qwerty:
                    return "com.apple.keylayout.US"
                case .colemak:
                    return "com.apple.keylayout.Colemak"
                case .dvorak:
                    return "com.apple.keylayout.Dvorak"
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
            if let legacyValue = UserDefaults.standard.value(forKey: legacyKey) as? Bool,
               legacyValue {
                return .openAI
            }
            return .off
        }
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.aiBackend"
    }
}
