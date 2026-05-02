import Foundation
import Security

enum KeychainStore {

    private static func baseQuery(for provider: ProviderID) -> [CFString: Any] {
        [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "com.typeoh.\(provider.rawValue)",
            kSecAttrAccount: "apiKey",
        ]
    }

    @discardableResult
    static func save(key: String, for provider: ProviderID) -> Bool {
        let data = Data(key.utf8)

        // Try update first (item may already exist)
        let updateStatus = SecItemUpdate(
            baseQuery(for: provider) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }

        // Item didn't exist — add it
        var addQuery = baseQuery(for: provider)
        addQuery[kSecValueData]       = data
        addQuery[kSecAttrAccessible]  = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus != errSecSuccess {
            NSLog("[Type.OH] Keychain save failed for %@: OSStatus %d", provider.rawValue, addStatus)
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
