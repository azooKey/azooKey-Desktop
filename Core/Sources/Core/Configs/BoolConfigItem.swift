import Foundation

protocol BoolConfigItem: ConfigItem<Bool> {
    static var `default`: Bool { get }
}

extension BoolConfigItem {
    public var value: Bool {
        get {
            if let value = UserDefaults.standard.value(forKey: Self.key) {
                value as? Bool ?? Self.default
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
    /// デバッグウィンドウにd/Dで遷移する設定
    public struct DebugWindow: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.debug.enableDebugWindow"
    }
    /// ライブ変換を有効化する設定
    public struct LiveConversion: BoolConfigItem {
        public init() {}
        static let `default` = true
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.enableLiveConversion"
    }
    /// 円マークの代わりにバックスラッシュを入力する設定
    public struct TypeBackSlash: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeBackSlash"
    }
    /// 「　」の代わりに「 」を入力する設定
    public struct TypeHalfSpace: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeHalfSpace"
    }
    /// AI変換時にコンテキストを含めるかどうか
    public struct IncludeContextInAITransform: BoolConfigItem {
        public init() {}
        static let `default` = true
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.includeContextInAITransform"
    }
}
