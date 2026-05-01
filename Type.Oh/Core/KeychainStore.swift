import Foundation
import Security

enum KeychainStore {
    static func save(key: String, for provider: ProviderID) {
        let service = "com.typeoh.\(provider.rawValue)"
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "apiKey"
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData] = Data(key.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load(for provider: ProviderID) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "com.typeoh.\(provider.rawValue)",
            kSecAttrAccount: "apiKey",
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for provider: ProviderID) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "com.typeoh.\(provider.rawValue)",
            kSecAttrAccount: "apiKey"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
