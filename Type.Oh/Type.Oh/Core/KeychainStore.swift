import Foundation
import Security

enum KeychainStore {

    // kSecUseDataProtectionKeychain = true targets the modern data-protection keychain,
    // which avoids the legacy file-based keychain prompt on macOS (even without sandbox).
    private static func baseQuery(for provider: ProviderID) -> [CFString: Any] {
        [
            kSecClass:                   kSecClassGenericPassword,
            kSecAttrService:             "com.typeoh.\(provider.rawValue)",
            kSecAttrAccount:             "apiKey",
            kSecUseDataProtectionKeychain: true as Any,
        ]
    }

    @discardableResult
    static func save(key: String, for provider: ProviderID) -> Bool {
        var query = baseQuery(for: provider)
        let data = Data(key.utf8)

        // Try update first (item may already exist)
        let updateAttrs: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)

        if updateStatus == errSecSuccess {
            return true
        }

        // Item didn't exist — add it
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        let addStatus = SecItemAdd(query as CFDictionary, nil)

        if addStatus != errSecSuccess {
            NSLog("[Type.OH] Keychain save failed for %@: %d", provider.rawValue, addStatus)
        }
        return addStatus == errSecSuccess
    }

    static func load(for provider: ProviderID) -> String? {
        var query = baseQuery(for: provider)
        query[kSecReturnData]  = true
        query[kSecMatchLimit]  = kSecMatchLimitOne

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for provider: ProviderID) {
        SecItemDelete(baseQuery(for: provider) as CFDictionary)
    }
}
