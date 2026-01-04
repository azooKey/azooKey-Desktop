extension Config {
    enum Deprecated {}
}

extension Config.Deprecated {
    /// 「、」「。」の代わりに「,」「.」を入力する設定
    /// - note: この設定はv0.1.2以降PunctuationStyleで置き換える
    struct TypeCommaAndPeriod: BoolConfigItem {
        static let `default` = false
        static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.typeCommaAndPeriod"
    }

    /// Zenzaiを利用する設定
    /// - note: この設定はv0.1.2以降廃止。常時有効になる。
    @available(*, deprecated, message: "ZenzaiIntegration.value is always true")
    struct ZenzaiIntegration: BoolConfigItem {
        static let `default` = true
        static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.enableZenzai"
    }

    /// OpenAI APIキー有効化設定
    /// - note: この設定はAIBackendPreferenceで置き換える。マイグレーション用にのみ残す。
    @available(*, deprecated, message: "Use AIBackendPreference instead")
    struct EnableOpenAiApiKey: BoolConfigItem {
        static let `default` = false
        static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.enableOpenAiApiKey"
    }
}
