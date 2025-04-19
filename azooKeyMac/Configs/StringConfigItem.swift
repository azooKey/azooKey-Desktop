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

        // keychainで保存
        var value: String {
            get {
                KeychainHelper.read(key: Self.key) ?? ""
            }
            nonmutating set {
                KeychainHelper.save(key: Self.key, value: newValue)
            }
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
