import Foundation

/// namespace for `Config`
public enum Config {
    nonisolated(unsafe) public static let userDefaults: UserDefaults = {
        #if os(macOS)
        UserDefaults(suiteName: AppGroup.azooKeyMacIdentifier) ?? .standard
        #else
        .standard
        #endif
    }()

    public static func object(forKey key: String) -> Any? {
        if let value = Self.userDefaults.object(forKey: key) {
            return value
        }
        return UserDefaults.standard.object(forKey: key)
    }

    public static func data(forKey key: String) -> Data? {
        if let value = Self.userDefaults.data(forKey: key) {
            return value
        }
        return UserDefaults.standard.data(forKey: key)
    }

    public static func string(forKey key: String) -> String? {
        if let value = Self.userDefaults.string(forKey: key) {
            return value
        }
        return UserDefaults.standard.string(forKey: key)
    }

    public static func set(_ value: Any?, forKey key: String) {
        Self.userDefaults.set(value, forKey: key)
    }
}

public protocol ConfigItem<Value> {
    static var key: String { get }
    associatedtype Value: Codable
    var value: Value { get nonmutating set }
}
