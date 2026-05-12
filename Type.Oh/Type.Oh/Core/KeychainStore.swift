import Foundation
import Security

/// Per-provider API key storage.
///
/// macOS keychain prompts the user with a password dialog whenever an item is
/// read by a binary that isn't on its ACL — and in dev / unsigned builds, that
/// happens after every rebuild. Three things tame the prompt-storm:
///
/// 1. **In-memory cache.** Each provider's key is fetched at most once per app
///    launch. Subsequent reads return from cache (`load`, `provider(for:)`,
///    every AI generation).
/// 2. **Existence probe.** `hasKey(for:)` uses `kSecReturnAttributes` (no
///    data return) — checking that an item exists does *not* trigger the
///    prompt. Used by Setup / Settings to display "Configured" without
///    forcing a real load.
/// 3. **Lazy reveal.** The UI no longer eagerly calls `load` on appear; the
///    user explicitly taps Reveal to inspect a stored key.
enum KeychainStore {

    // MARK: - Cache

    /// `nil` value = "we tried and the keychain returned no item".
    /// Absence from the dict = "we haven't tried yet this session".
    nonisolated(unsafe) private static var cache: [ProviderID: String?] = [:]
    private static let cacheLock = NSLock()

    private static func cached(_ provider: ProviderID) -> (hit: Bool, value: String?) {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let entry = cache[provider] { return (true, entry) }
        return (false, nil)
    }

    private static func setCached(_ provider: ProviderID, _ value: String?) {
        cacheLock.lock(); cache[provider] = value; cacheLock.unlock()
    }

    private static func clearCache(_ provider: ProviderID) {
        cacheLock.lock(); cache.removeValue(forKey: provider); cacheLock.unlock()
    }

    // MARK: - Query

    private static func baseQuery(for provider: ProviderID) -> [CFString: Any] {
        [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: "com.typeoh.\(provider.rawValue)",
            kSecAttrAccount: "apiKey",
        ]
    }

    // MARK: - Public API

    /// Returns true if a key is stored for the provider. Does *not* prompt —
    /// attribute-only reads never trigger the keychain UI.
    static func hasKey(for provider: ProviderID) -> Bool {
        // Cache hit covers this without touching the keychain.
        let cached = cached(provider)
        if cached.hit { return cached.value != nil }

        var query = baseQuery(for: provider)
        query[kSecReturnAttributes] = true
        query[kSecMatchLimit]       = kSecMatchLimitOne

        var ignored: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ignored)
        return status == errSecSuccess
    }

    /// Loads the key from cache if present, otherwise from the keychain.
    /// **May prompt the user** on the first call per session if the keychain
    /// hasn't trusted this binary. Subsequent calls are silent.
    static func load(for provider: ProviderID) -> String? {
        let cached = cached(provider)
        if cached.hit { return cached.value }

        var query = baseQuery(for: provider)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        let loaded: String?
        if status == errSecSuccess, let data = result as? Data {
            loaded = String(data: data, encoding: .utf8)
        } else {
            loaded = nil
        }
        setCached(provider, loaded)
        return loaded
    }

    @discardableResult
    static func save(key: String, for provider: ProviderID) -> Bool {
        let data = Data(key.utf8)

        let updateStatus = SecItemUpdate(
            baseQuery(for: provider) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            setCached(provider, key)
            return true
        }

        var addQuery = baseQuery(for: provider)
        addQuery[kSecValueData]      = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        if addStatus != errSecSuccess {
            NSLog("[Type.OH] Keychain save failed for %@: OSStatus %d", provider.rawValue, addStatus)
            return false
        }
        setCached(provider, key)
        return true
    }

    static func delete(for provider: ProviderID) {
        SecItemDelete(baseQuery(for: provider) as CFDictionary)
        setCached(provider, nil)
    }

    /// Background pre-warm. Loads the key for `provider` into the cache so the
    /// first AI generation doesn't surprise the user with a prompt mid-flow.
    /// On unsigned dev builds this still produces *one* prompt at launch, but
    /// the user only sees it once per session.
    static func prefetch(_ provider: ProviderID) {
        guard provider != .appleOnDevice else { return }
        _ = load(for: provider)
    }
}
