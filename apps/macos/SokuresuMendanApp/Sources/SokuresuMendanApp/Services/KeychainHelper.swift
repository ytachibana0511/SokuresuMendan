import CryptoKit
import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.sokuresumendan.app"
    private static let account = "profile-encryption-key"

    static func loadOrCreateSymmetricKey() throws -> SymmetricKey {
        if let existing = try? loadData() {
            return SymmetricKey(data: existing)
        }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try saveData(data)
        return key
    }

    private static func loadData() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: "KeychainHelper", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychainから暗号鍵を取得できませんでした。"
            ])
        }
        return data
    }

    private static func saveData(_ data: Data) throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainHelper", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychainへ暗号鍵を保存できませんでした。"
            ])
        }
    }
}
