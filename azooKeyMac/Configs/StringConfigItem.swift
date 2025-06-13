//
//  StringConfigItem.swift
//  azooKeyMac
//
//  Created by miwa on 2024/04/27.
//

import Foundation

protocol StringConfigItem: ConfigItem<String> {}

extension StringConfigItem {
    var value: String {
        get {
            UserDefaults.standard.string(forKey: Self.key) ?? ""
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: Self.key)
        }
    }
}

extension Config {
    /// 統合されたLLM API Key（プロバイダーに応じて使用される）
    struct LLMApiKey: StringConfigItem {
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiApiKey"
    }
}

extension Config {
    struct ZenzaiProfile: StringConfigItem {
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.ZenzaiProfile"
    }
}

extension Config {
    /// OpenAIモデル名
    struct OpenAiModelName: StringConfigItem {
        static var `default`: String = "gpt-4o-mini"
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiModelName"
    }

    /// プロンプト履歴（JSON形式で保存）
    struct PromptHistory: StringConfigItem {
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.PromptHistory"
    }

    /// LLMプロバイダー
    struct LLMProvider: StringConfigItem {
        static var `default`: String = "openai"
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.LLMProvider"

        var value: String {
            get {
                UserDefaults.standard.string(forKey: Self.key) ?? Self.default
            }
            nonmutating set {
                UserDefaults.standard.set(newValue, forKey: Self.key)
            }
        }
    }

    /// カスタムLLMエンドポイントURL
    struct CustomLLMEndpoint: StringConfigItem {
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.CustomLLMEndpoint"
    }

    /// Geminiモデル名
    struct GeminiModelName: StringConfigItem {
        static var `default`: String = "gemini-1.5-flash"
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.GeminiModelName"

        var value: String {
            get {
                UserDefaults.standard.string(forKey: Self.key) ?? Self.default
            }
            nonmutating set {
                UserDefaults.standard.set(newValue, forKey: Self.key)
            }
        }
    }
}
