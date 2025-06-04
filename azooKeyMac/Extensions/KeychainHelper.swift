import Foundation
import Security

enum KeychainHelper {
    static func save(key: String, value: String) async {
        await withCheckedContinuation { continuation in
            Task.detached {
                guard let data = value.data(using: .utf8) else {
                    print("StringをDataに変換する際にエラーが発生しました")
                    continuation.resume()
                    return
                }

                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: key,
                    kSecValueData as String: data
                ]

                // 既存のデータがあれば削除
                SecItemDelete(query as CFDictionary)

                // 新しいデータを追加
                SecItemAdd(query as CFDictionary, nil)
                continuation.resume()
            }
        }
    }

    static func read(key: String) async -> String? {
        await withCheckedContinuation { continuation in
            Task.detached {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: key,
                    kSecReturnData as String: kCFBooleanTrue!,
                    kSecMatchLimit as String: kSecMatchLimitOne
                ]

                var dataTypeRef: AnyObject?
                let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

                if status == errSecSuccess, let data = dataTypeRef as? Data {
                    continuation.resume(returning: String(bytes: data, encoding: .utf8))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func delete(key: String) async {
        await withCheckedContinuation { continuation in
            Task.detached {
                let query: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrAccount as String: key
                ]

                SecItemDelete(query as CFDictionary)
                continuation.resume()
            }
        }
    }
}
