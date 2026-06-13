import Core

extension ConverterServer {
    @MainActor
    static func makeSettingDescriptors(
        capabilities: ConverterSettingClientCapabilities
    ) -> [ConverterSettingDescriptor] {
        func descriptor(
            key: String,
            title: String,
            section: String,
            kind: ConverterSettingKind,
            value: ConverterSettingValue? = nil,
            isEnabled: Bool = true
        ) -> ConverterSettingDescriptor {
            ConverterSettingDescriptor(
                key: key,
                title: title,
                section: section,
                kind: kind,
                value: value,
                isEnabled: isEnabled,
                requiresClientUpdate: requiresClientUpdate(kind: kind, capabilities: capabilities)
            )
        }

        return [
            descriptor(
                key: Config.AIBackendPreference.key,
                title: "いい感じ変換",
                section: "基本",
                kind: .selector(options: [
                    .init(title: "オフ", value: .string(Config.AIBackendPreference.Value.off.rawValue)),
                    .init(title: "Foundation Models", value: .string(Config.AIBackendPreference.Value.foundationModels.rawValue)),
                    .init(title: "OpenAI API", value: .string(Config.AIBackendPreference.Value.openAI.rawValue))
                ]),
                value: .string(Config.AIBackendPreference().value.rawValue)
            ),
            descriptor(
                key: Config.LiveConversion.key,
                title: "ライブ変換",
                section: "変換設定",
                kind: .toggle,
                value: .bool(Config.LiveConversion().value)
            ),
            descriptor(
                key: Config.TypeBackSlash.key,
                title: "円記号の代わりにバックスラッシュを入力",
                section: "入力オプション",
                kind: .toggle,
                value: .bool(Config.TypeBackSlash().value)
            ),
            descriptor(
                key: Config.TypeHalfSpace.key,
                title: "スペースは常に半角を入力",
                section: "入力オプション",
                kind: .toggle,
                value: .bool(Config.TypeHalfSpace().value)
            ),
            descriptor(
                key: Config.OptionDirectFullWidthInput.key,
                title: "Optionキーで直接全角英数を入力",
                section: "入力オプション",
                kind: .toggle,
                value: .bool(Config.OptionDirectFullWidthInput().value)
            ),
            descriptor(
                key: Config.PunctuationStyle.key,
                title: "句読点の種類",
                section: "入力オプション",
                kind: .selector(options: [
                    .init(title: "、と。", value: .int(Config.PunctuationStyle.Value.kutenAndToten.rawValue)),
                    .init(title: "、と．", value: .int(Config.PunctuationStyle.Value.periodAndToten.rawValue)),
                    .init(title: "，と。", value: .int(Config.PunctuationStyle.Value.kutenAndComma.rawValue)),
                    .init(title: "，と．", value: .int(Config.PunctuationStyle.Value.periodAndComma.rawValue))
                ]),
                value: .int(Config.PunctuationStyle().value.rawValue)
            ),
            descriptor(
                key: Config.Learning.key,
                title: "履歴学習",
                section: "履歴学習",
                kind: .selector(options: [
                    .init(title: "学習する", value: .string(Config.Learning.Value.inputAndOutput.rawValue)),
                    .init(title: "学習を停止", value: .string(Config.Learning.Value.onlyOutput.rawValue)),
                    .init(title: "学習を無視", value: .string(Config.Learning.Value.nothing.rawValue))
                ]),
                value: .string(Config.Learning().value.rawValue)
            ),
            descriptor(
                key: "dev.ensan.inputmethod.azooKeyMac.setting.action.resetLearningData",
                title: "履歴学習データをリセット",
                section: "履歴学習",
                kind: .button(action: "resetLearningData")
            ),
            descriptor(
                key: Config.InputStyle.key,
                title: "入力方式",
                section: "入力方式",
                kind: .custom(surface: "inputStyle")
            ),
            descriptor(
                key: Config.KeyboardLayout.key,
                title: "キーボード配列",
                section: "キーボード配列",
                kind: .selector(options: [
                    .init(title: "QWERTY", value: .string(Config.KeyboardLayout.Value.qwerty.rawValue)),
                    .init(title: "Australian", value: .string(Config.KeyboardLayout.Value.australian.rawValue)),
                    .init(title: "British", value: .string(Config.KeyboardLayout.Value.british.rawValue)),
                    .init(title: "Colemak", value: .string(Config.KeyboardLayout.Value.colemak.rawValue)),
                    .init(title: "Dvorak", value: .string(Config.KeyboardLayout.Value.dvorak.rawValue)),
                    .init(title: "Dvorak - QWERTY Command", value: .string(Config.KeyboardLayout.Value.dvorakQwertyCommand.rawValue))
                ]),
                value: .string(Config.KeyboardLayout().value.rawValue)
            ),
            descriptor(
                key: Config.ZenzaiProfile.key,
                title: "変換プロフィール",
                section: "変換設定",
                kind: .textField(secure: false),
                value: .string(Config.ZenzaiProfile().value)
            ),
            descriptor(
                key: Config.ZenzaiInferenceLimit.key,
                title: "Zenzaiの推論上限",
                section: "変換設定",
                kind: .number(min: 1, max: 50, step: 1),
                value: .int(Config.ZenzaiInferenceLimit().value)
            ),
            descriptor(
                key: Config.ZenzaiPersonalizationLevel.key,
                title: "パーソナライズ",
                section: "開発者向け設定",
                kind: .selector(options: [
                    .init(title: "オフ", value: .string(Config.ZenzaiPersonalizationLevel.Value.off.rawValue)),
                    .init(title: "弱く", value: .string(Config.ZenzaiPersonalizationLevel.Value.soft.rawValue)),
                    .init(title: "普通", value: .string(Config.ZenzaiPersonalizationLevel.Value.normal.rawValue)),
                    .init(title: "強く", value: .string(Config.ZenzaiPersonalizationLevel.Value.hard.rawValue))
                ]),
                value: .string(Config.ZenzaiPersonalizationLevel().value.rawValue)
            ),
            descriptor(
                key: Config.DebugPredictiveTyping.key,
                title: "開発中の予測入力を有効化",
                section: "開発者向け設定",
                kind: .toggle,
                value: .bool(Config.DebugPredictiveTyping().value)
            ),
            descriptor(
                key: Config.DebugTypoCorrection.key,
                title: "開発中の入力訂正を有効化",
                section: "開発者向け設定",
                kind: .toggle,
                value: .bool(Config.DebugTypoCorrection().value)
            ),
            descriptor(
                key: "dev.ensan.inputmethod.azooKeyMac.setting.action.downloadDebugTypoCorrectionWeights",
                title: "入力訂正の重みをダウンロード",
                section: "開発者向け設定",
                kind: .button(action: "downloadDebugTypoCorrectionWeights")
            ),
            descriptor(
                key: Config.UserDictionary.key,
                title: "ユーザー辞書",
                section: "辞書設定",
                kind: .custom(surface: "userDictionary")
            ),
            descriptor(
                key: Config.SystemUserDictionary.key,
                title: "システム辞書",
                section: "辞書設定",
                kind: .custom(surface: "systemUserDictionary")
            ),
            descriptor(
                key: "dev.ensan.inputmethod.azooKeyMac.setting.surface.foundationModelsAvailability",
                title: "Foundation Models availability",
                section: "基本",
                kind: .custom(surface: "foundationModelsAvailability")
            ),
            descriptor(
                key: Config.OpenAiModelName.key,
                title: "OpenAIモデル名",
                section: "OpenAI API",
                kind: .textField(secure: false),
                value: .string(Config.OpenAiModelName().value.isEmpty ? Config.OpenAiModelName.default : Config.OpenAiModelName().value)
            ),
            descriptor(
                key: Config.OpenAiApiEndpoint.key,
                title: "OpenAI APIエンドポイント",
                section: "OpenAI API",
                kind: .textField(secure: false),
                value: .string(Config.OpenAiApiEndpoint().value)
            ),
            descriptor(
                key: "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiApiKey",
                title: "OpenAI APIキー",
                section: "OpenAI API",
                kind: .textField(secure: true)
            )
        ]
    }

    private static func requiresClientUpdate(
        kind: ConverterSettingKind,
        capabilities: ConverterSettingClientCapabilities
    ) -> Bool {
        guard capabilities.supportedKinds.contains(kind.identifier) else {
            return true
        }
        switch kind {
        case .button(let action):
            return !capabilities.supportedActions.contains(action)
        case .custom(let surface):
            return !capabilities.supportedCustomSurfaces.contains(surface)
        case .toggle, .selector, .textField, .number:
            return false
        }
    }

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity
    static func updateSetting(key: String, value: ConverterSettingValue) throws {
        switch key {
        case Config.AIBackendPreference.key:
            guard case .string(let rawValue) = value,
                  let backend = Config.AIBackendPreference.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.AIBackendPreference().value = backend
        case Config.LiveConversion.key:
            Config.LiveConversion().value = try boolSettingValue(value, key: key)
        case Config.TypeBackSlash.key:
            Config.TypeBackSlash().value = try boolSettingValue(value, key: key)
        case Config.TypeHalfSpace.key:
            Config.TypeHalfSpace().value = try boolSettingValue(value, key: key)
        case Config.OptionDirectFullWidthInput.key:
            Config.OptionDirectFullWidthInput().value = try boolSettingValue(value, key: key)
        case Config.PunctuationStyle.key:
            guard case .int(let rawValue) = value,
                  let punctuationStyle = Config.PunctuationStyle.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.PunctuationStyle().value = punctuationStyle
        case Config.Learning.key:
            guard case .string(let rawValue) = value,
                  let learning = Config.Learning.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.Learning().value = learning
        case Config.KeyboardLayout.key:
            guard case .string(let rawValue) = value,
                  let layout = Config.KeyboardLayout.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.KeyboardLayout().value = layout
        case Config.ZenzaiProfile.key:
            guard case .string(let value) = value else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.ZenzaiProfile().value = value
        case Config.ZenzaiInferenceLimit.key:
            guard case .int(let value) = value, (1 ... 50).contains(value) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.ZenzaiInferenceLimit().value = value
        case Config.ZenzaiPersonalizationLevel.key:
            guard case .string(let rawValue) = value,
                  let level = Config.ZenzaiPersonalizationLevel.Value(rawValue: rawValue) else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.ZenzaiPersonalizationLevel().value = level
        case Config.DebugPredictiveTyping.key:
            Config.DebugPredictiveTyping().value = try boolSettingValue(value, key: key)
        case Config.DebugTypoCorrection.key:
            Config.DebugTypoCorrection().value = try boolSettingValue(value, key: key)
        case Config.OpenAiModelName.key:
            guard case .string(let value) = value else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.OpenAiModelName().value = value
        case Config.OpenAiApiEndpoint.key:
            guard case .string(let value) = value else {
                throw ConverterServerError.invalidSettingValue(key)
            }
            Config.OpenAiApiEndpoint().value = value
        default:
            throw ConverterServerError.unknownSetting(key)
        }
    }

    private static func boolSettingValue(_ value: ConverterSettingValue, key: String) throws -> Bool {
        guard case .bool(let boolValue) = value else {
            throw ConverterServerError.invalidSettingValue(key)
        }
        return boolValue
    }
}
