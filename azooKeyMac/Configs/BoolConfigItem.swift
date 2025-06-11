import Foundation

protocol BoolConfigItem: ConfigItem<Bool> {
    static var `default`: Bool { get }
}

extension BoolConfigItem {
    var value: Bool {
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
    struct DebugWindow: BoolConfigItem {
        static let `default` = false
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.debug.enableDebugWindow"
    }
    /// ライブ変換を有効化する設定
    struct LiveConversion: BoolConfigItem {
        static let `default` = true
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.enableLiveConversion"
    }
    /// 円マークの代わりにバックスラッシュを入力する設定
    struct TypeBackSlash: BoolConfigItem {
        static let `default` = false
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeBackSlash"
    }
    /// 「、」「。」の代わりに「,」「.」を入力する設定
    struct TypeCommaAndPeriod: BoolConfigItem {
        static let `default` = false
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeCommaAndPeriod"
    }
    /// 「　」の代わりに「 」を入力する設定
    struct TypeHalfSpace: BoolConfigItem {
        static let `default` = false
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeHalfSpace"
    }
    /// Zenzaiを利用する設定
    struct ZenzaiIntegration: BoolConfigItem {
        static let `default` = true
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.enableZenzai"
    }
    /// OpenAI APIキー
    struct EnableOpenAiApiKey: BoolConfigItem {
        static let `default` = false
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.enableOpenAiApiKey"
    }
    /// AI変換時にコンテキストを含めるかどうか
    struct IncludeContextInAITransform: BoolConfigItem {
        static let `default` = true
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.includeContextInAITransform"
    }
}
