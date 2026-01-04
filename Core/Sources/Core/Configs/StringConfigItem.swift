//
//  StringConfigItem.swift
//  azooKeyMac
//
//  Created by miwa on 2024/04/27.
//

import Foundation

protocol StringConfigItem: ConfigItem<String> {}

extension StringConfigItem {
    public var value: String {
        get {
            UserDefaults.standard.string(forKey: Self.key) ?? ""
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: Self.key)
        }
    }
}

extension Config {
    public struct ZenzaiProfile: StringConfigItem {
        public init() {}
        
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.ZenzaiProfile"
    }
}

extension Config {
    /// OpenAIモデル名
    public struct OpenAiModelName: StringConfigItem {
        public init() {}

        public static let `default`: String = "gpt-4o-mini"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiModelName"
    }

    /// OpenAI API エンドポイント
    public struct OpenAiApiEndpoint: StringConfigItem {
        public init() {}

        public static let `default` = "https://api.openai.com/v1/chat/completions"
        public static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiApiEndpoint"

        public var value: String {
            get {
                let stored = UserDefaults.standard.string(forKey: Self.key) ?? ""
                return stored.isEmpty ? Self.default : stored
            }
            nonmutating set {
                UserDefaults.standard.set(newValue, forKey: Self.key)
            }
        }
    }

    /// プロンプト履歴（JSON形式で保存）
    struct PromptHistory: StringConfigItem {
        static let key: String = "dev.ensan.inputmethod.azooKeyMac.preference.PromptHistory"
    }
}
