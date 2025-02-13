//
//  BoolConfigItem.swift
//  azooKeyMac
//
//  Created by miwa on 2024/04/27.
//

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
    /// 英語変換を有効化する設定
    struct EnglishConversion: BoolConfigItem {
        static let `default` = false
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.enableEnglishConversion"
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
    /// OpenAI APIキー
    struct UseCustomZenzModel: BoolConfigItem {
        static let `default` = false
        static var key: String = "dev.ensan.inputmethod.azooKeyMac.preference.useCustomZenzModel"
        static func customZenzDirectoryURL(applicationSupportDirectory: URL) -> URL {
            if #available(macOS 13, *) {
                applicationSupportDirectory.appending(path: "gguf", directoryHint: .isDirectory)
            } else {
                applicationSupportDirectory.appendingPathComponent("gguf", isDirectory: true)
            }
        }
        static func customZenzFileURL(applicationSupportDirectory: URL) -> URL {
            if #available(macOS 13, *) {
                customZenzDirectoryURL(applicationSupportDirectory: applicationSupportDirectory)
                    .appending(path: "custom_zenz_model.gguf", directoryHint: .notDirectory)
            } else {
                customZenzDirectoryURL(applicationSupportDirectory: applicationSupportDirectory)
                    .appendingPathComponent("custom_zenz_model.gguf", isDirectory: false)
            }
        }
    }
}
