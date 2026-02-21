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
                return Self.default
            }
        }
        nonmutating set {
            do {
                let encoded = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(encoded, forKey: Self.key)
            } catch {
                // エンコード失敗時は何もしない
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
