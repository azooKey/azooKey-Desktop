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

        private static var cachedValue: String = ""
        private static var isLoaded: Bool = false

        // keychainで保存
        var value: String {
            get {
                if !Self.isLoaded {
                    Task {
                        Self.cachedValue = await KeychainHelper.read(key: Self.key) ?? ""
                        Self.isLoaded = true
                    }
                }
                return Self.cachedValue
            }
            nonmutating set {
                Self.cachedValue = newValue
                Task {
                    await KeychainHelper.save(key: Self.key, value: newValue)
                }
            }
        }

        // 初期化時にKeychainから値を読み込む
        static func loadFromKeychain() async {
            cachedValue = await KeychainHelper.read(key: key) ?? ""
            isLoaded = true
        }
    }
}

extension Config {
    struct ZenzaiProfile: StringConfigItem {
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.ZenzaiProfile"
    }
}

extension Config {
    /// LLMモデル名（プロバイダーに応じて使用される）
    struct LLMModelName: StringConfigItem {
        static var `default`: String = "gpt-4o-mini"
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiModelName"

        var value: String {
            get {
                UserDefaults.standard.string(forKey: Self.key) ?? Self.default
            }
            nonmutating set {
                UserDefaults.standard.set(newValue, forKey: Self.key)
            }
        }
    }

    /// プロンプト履歴（JSON形式で保存）
    struct PromptHistory: StringConfigItem {
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.PromptHistory"
    }

    /// LLMプロバイダー（openai, gemini, custom）
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

    /// カスタムLLMエンドポイントURL（OpenAI API互換）
    struct CustomLLMEndpoint: StringConfigItem {
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.CustomLLMEndpoint"
    }
}
