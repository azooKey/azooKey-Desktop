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
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.LLMApiKey"
        // 旧OpenAI API Keyとの互換性のため
        private static let legacyOpenAIKey: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiApiKey"

        private static var cachedValue: String = ""
        private static var isLoaded: Bool = false

        // keychainで保存
        var value: String {
            get {
                if !Self.isLoaded {
                    Task {
                        await Self.loadFromKeychain()
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

        // 初期化時にKeychainから値を読み込む（マイグレーション処理含む）
        static func loadFromKeychain() async {
            // 新しいキーから読み込み
            cachedValue = await KeychainHelper.read(key: key) ?? ""

            // 新しいキーが空で、旧OpenAI Keyが存在する場合はマイグレーション
            if cachedValue.isEmpty {
                if let legacyValue = await KeychainHelper.read(key: legacyOpenAIKey), !legacyValue.isEmpty {
                    cachedValue = legacyValue
                    // 新しいキーに保存
                    await KeychainHelper.save(key: key, value: legacyValue)
                }
            }

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
