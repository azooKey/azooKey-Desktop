import Foundation

protocol IntConfigItem: ConfigItem<Int> {
    static var `default`: Int { get }
}

extension IntConfigItem {
    public var value: Int {
        get {
            if let value = UserDefaults.standard.value(forKey: Self.key) {
                value as? Int ?? Self.default
            } else {
                Self.default
            }
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: Self.key)
        }
    }
}

extension Config {
    public struct ZenzaiInferenceLimit: IntConfigItem {
        public init() {}
        static let `default` = 1
        public static let key = "dev.ensan.inputmethod.azooKeyMac.preference.zenzaiInferenceLimit"
    }
}
