import Foundation

extension Config {
    struct PunctuationStyle: ConfigItem {
        enum Value: Int, Codable, Equatable, Hashable {
            case kutenAndToten = 1
            case kutenAndComma = 2
            case periodAndToten = 3
            case periodAndComma = 4
        }
        static var `default`: Value = .`kutenAndToten`
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.punctuation_style"
    }
}

extension Config.PunctuationStyle {
    var value: Value {
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
