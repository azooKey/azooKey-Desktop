import Foundation

extension Config {
    public struct PunctuationStyle: ConfigItem {
        public enum Value: Int, Codable, Equatable, Hashable, Sendable {
            case kutenAndToten = 1
            case kutenAndComma = 2
            case periodAndToten = 3
            case periodAndComma = 4
        }

        public init() {}
        public static let `default`: Value = .`kutenAndToten`
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.punctuation_style"
    }
}

extension Config.PunctuationStyle {
    public var value: Value {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.key) else {
                print(#file, #line, "data is not set yet")
                // この場合、過去の設定を反映する
                return if Config.Deprecated.TypeCommaAndPeriod().value {
                    .periodAndComma
                } else {
                    Self.default
                }
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
