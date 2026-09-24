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
            guard let data = Config.data(forKey: Self.key) else {
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
                Config.set(encoded, forKey: Self.key)
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
            case australian
            case british
            case colemak
            case dvorak
            case dvorakQwertyCommand
            case programmerDvorakJIS
            case programmerDvorakUS

            public var layoutIdentifier: String {
                /// 【独自の keyRemapTable を持つ配列を追加する際の注意】
                /// 1. 対象キーボードに応じた識別子を返却し、それを基準に辞書を作成すること
                ///    OSはここで指定された識別子に従って論理キーを生成し、azooKeyに渡します。
                ///    JISキーボード用として追加する場合は「com.apple.keylayout.Romaji」を、
                ///    USキーボード用として追加する場合は「com.apple.keylayout.US」を必ず返却してください。
                ///    その上で、追加する配列の変換辞書（keyRemapTable）は、
                ///    この戻り値によってOSから送られてくる論理文字を前提として記述する必要があります。
                /// 2. 必ずJIS用とUS用の2つの独立した case を用意し、1つに統合しないこと
                ///    独自の変換マップ（keyRemapTable）を持つ配列は、記号出力をOSに委ねる標準配列とは異なり、
                ///    ベースとなるJIS/USの前提が一致しないと出力が完全に破綻します。
                ///    OSによるキーボードのJIS/US誤認識が発生した際、ユーザーが手動で正しい配列を
                ///    選択して回避できる手段を残しておく必要があるため、内部での自動判定は避けてください。
                switch self {
                case .qwerty:
                    return "com.apple.keylayout.US"
                case .australian:
                    return "com.apple.keylayout.Australian"
                case .british:
                    return "com.apple.keylayout.British"
                case .colemak:
                    return "com.apple.keylayout.Colemak"
                case .dvorak:
                    return "com.apple.keylayout.Dvorak"
                case .dvorakQwertyCommand:
                    return "com.apple.keylayout.DVORAK-QWERTYCMD"
                case .programmerDvorakJIS:
                    return "com.apple.keylayout.Romaji"
                case .programmerDvorakUS:
                    return "com.apple.keylayout.US"
                }
            }

            public var hasDistinctBackSlashAndYen: Bool {
                /// 【独自の keyRemapTable を追加した配列専用の設定】
                ///　「¥」と「\」が両方存在する場合にtrueを返却する処理を追加すること
                switch self {
                case .programmerDvorakJIS:
                    return true
                default:
                    return false
                }
            }

            public func jisZeroKeyOutput(isShiftPressed: Bool) -> String? {
                /// 【独自の keyRemapTable を追加した配列専用の設定】
                /// JISに於いて「0」はShift押下有無にかかわらず常に "0" が送られる。
                /// Shiftの有無を区別して変換できないため、isShiftPressedに応じた文字返却をして下さい。
                switch self {
                case .programmerDvorakJIS:
                    if isShiftPressed {
                        return "6"
                    } else {
                        return "]"
                    }
                default:
                    // QWERTYなど対象外の配列は nil を返し、元の処理（default: での辞書翻訳など）へ流す
                    return nil
                }
            }

            public func jisUnderscoreKeyOutput(isShiftPressed: Bool, isOptionPressed: Bool, typeBackSlash: Bool) -> String? {
                /// 【独自の keyRemapTable を追加した配列専用の設定】
                /// JISに於いて「_」はShift押下有無にかかわらず常に "_" が送られる。
                /// Shiftの有無を区別して変換できないため、isShiftPressedに応じた文字返却をして下さい。
                switch self {
                case .programmerDvorakJIS:
                    if isShiftPressed {
                        return "|"
                    } else if isOptionPressed {
                        // Option押下時は標準仕様との整合性を取るため、通常時と出力を逆転させる
                        if typeBackSlash {
                            // 設定ONの時、通常時は「¥」だが、Option時は本来の「\」を出力
                            return "\\"
                        } else {
                            // 設定OFFの時、通常時は「\」だが、Option時は「¥」を出力
                            return "¥"
                        }
                    } else {
                        // 通常時 (Unshifted)
                        if typeBackSlash {
                            // 「¥」と「\」の専用キーが両方存在するため、
                            // 設定がONの場合は、本来の文字「\」ではなく「¥」を出力
                            return "¥"
                        } else {
                            // 設定がOFFの場合は、本来の文字「\」を出力
                            return "\\"
                        }
                    }
                default:
                    // QWERTYなど対象外の配列は nil を返し、元の処理（default: での辞書翻訳など）へ流す
                    return nil
                }
            }

            public var keyRemapTable: [Character: Character]? {
                /// 【独自配列用の論理キー変換辞書】
                /// 論理キーを別の文字に変換するマッピング辞書です。
                /// OSから送られてくる論理文字をキー(Key)とし、配列特有の変換後の文字を値(Value)として定義してください。
                /// ※ JISの「_」や「0」など、OS仕様でShiftの区別ができないキーはここでは変換できません。専用関数で処理してください。
                switch self {
                case .programmerDvorakJIS:
                    return [
                        // JIS配列 Unshifted
                        "1":"&", "2":"[", "3":"{", "4":"}", "5":"(", "6":"=", "7":"*", "8":")", "9":"+", "0":"]",
                        "q":";", "w":",", "e":".", "r":"p", "t":"y", "y":"f", "u":"g", "i":"c", "o":"r", "p":"l", "@":"/", "[":"@",
                        "a":"a", "s":"o", "d":"e", "f":"u", "g":"i", "h":"d", "j":"h", "k":"t", "l":"n", ";":"s", ":":"-", "]":"$",
                        "z":"'", "x":"q", "c":"j", "v":"k", "b":"x", "n":"b", "m":"m", ",":"w", ".":"v", "/":"z", "\\":"\\",
                        "-":"!", "^":"#", "¥":"¥",

                        // JIS配列 Shifted
                        "!":"%", "\"":"7", "#":"5", "$":"3", "%":"1", "&":"9", "'":"0", "(":"2", ")":"4", "=":"8", "~":"`", "|":"|",
                        "Q":":", "W":"<", "E":">", "R":"P", "T":"Y", "Y":"F", "U":"G", "I":"C", "O":"R", "P":"L", "`":"?", "{":"^",
                        "A":"A", "S":"O", "D":"E", "F":"U", "G":"I", "H":"D", "J":"H", "K":"T", "L":"N", "+":"S", "*":"_", "}":"~",
                        "Z":"\"", "X":"Q", "C":"J", "V":"K", "B":"X", "N":"B", "M":"M", "<":"W", ">":"V", "?":"Z"
                    ]
                case .programmerDvorakUS:
                    return [
                        // US配列 Unshifted
                        "1":"&", "2":"[", "3":"{", "4":"}", "5":"(", "6":"=", "7":"*", "8":")", "9":"+", "0":"]",
                        "q":";", "w":",", "e":".", "r":"p", "t":"y", "y":"f", "u":"g", "i":"c", "o":"r", "p":"l", "[":"/", "]":"@",
                        "a":"a", "s":"o", "d":"e", "f":"u", "g":"i", "h":"d", "j":"h", "k":"t", "l":"n", ";":"s", "'":"-",
                        "z":"'", "x":"q", "c":"j", "v":"k", "b":"x", "n":"b", "m":"m", ",":"w", ".":"v", "/":"z", "\\":"\\",
                        "-":"!", "=":"#",

                        // US配列 Shifted
                        "!":"%", "@":"7", "#":"5", "$":"3", "%":"1", "^":"9", "&":"0", "*":"2", "(":"4", ")":"6", "_":"8", "+":"`",
                        "Q":":", "W":"<", "E":">", "R":"P", "T":"Y", "Y":"F", "U":"G", "I":"C", "O":"R", "P":"L", "{":"?", "}":"^",
                        "A":"A", "S":"O", "D":"E", "F":"U", "G":"I", "H":"D", "J":"H", "K":"T", "L":"N", ":":"S", "\"":"_",
                        "Z":"\"", "X":"Q", "C":"J", "V":"K", "B":"X", "N":"B", "M":"M", "<":"W", ">":"V", "?":"Z", "|":"|"
                    ]
                default:
                    // QWERTYなどの標準配列
                    return nil
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
            if let legacyValue = Config.object(forKey: legacyKey) as? Bool,
               legacyValue {
                return .openAI
            }
            return .off
        }
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.aiBackend"
    }
}
