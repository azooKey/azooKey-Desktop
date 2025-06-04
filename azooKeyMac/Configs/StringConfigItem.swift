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
    struct OpenAiApiKey: StringConfigItem {
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
    /// OpenAIモデル名
    struct OpenAiModelName: StringConfigItem {
        static var `default`: String = "gpt-4o-mini"
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.OpenAiModelName"
    }
}
