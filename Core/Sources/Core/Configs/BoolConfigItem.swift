import Foundation

protocol BoolConfigItem: ConfigItem<Bool> {
    static var `default`: Bool { get }
}

extension BoolConfigItem {
    public var value: Bool {
        get {
            if let value = Config.object(forKey: Self.key) {
                value as? Bool ?? Self.default
            } else {
                Self.default
            }
        }
        nonmutating set {
            Config.set(newValue, forKey: Self.key)
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
    /// 予測入力のデバッグ機能を有効化する設定
    public struct DebugPredictiveTyping: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.debug.predictiveTyping"
    }
    /// 入力訂正のデバッグ機能を有効化する設定
    public struct DebugTypoCorrection: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.debug.typoCorrection"
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
    /// 数字の直後の「.」「,」「:」「/」「-」を半角で入力する設定
    public struct TypeHalfWidthSymbolAfterNumber: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeHalfWidthSymbolAfterNumber"
    }
    /// 「/」で「・」ではなく「/」を入力する設定
    /// 日本語モードで変換中の文字がないときは、変換を待たずにすぐ入力する
    public struct TypeHalfWidthSlash: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeHalfWidthSlash"
    }
    /// Control+Lで全角英数ではなく半角英数に変換する設定
    public struct HalfWidthRomanWithControlL: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.halfWidthRomanWithControlL"
    }
    /// 「！」「（」などの全角記号の代わりに半角記号を入力する設定
    public struct TypeHalfWidthSymbol: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeHalfWidthSymbol"
    }
    /// Optionキー押下時に直接全角英数を入力する設定
    public struct OptionDirectFullWidthInput: BoolConfigItem {
        public init() {}
        static let `default` = false
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.optionDirectFullWidthInput"
    }
    /// AI変換時にコンテキストを含めるかどうか
    public struct IncludeContextInAITransform: BoolConfigItem {
        public init() {}
        static let `default` = true
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.includeContextInAITransform"
    }
}
