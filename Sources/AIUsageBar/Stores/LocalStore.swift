import Foundation
import CryptoKit
import Security
import UsageCore

/// Runs Keychain and disk work off the main actor. All errors fail closed; no plaintext saves.
actor LocalStore {
    static let shared = LocalStore()
    private let keys = StorageKey()
    private lazy var files = EncryptedJSONStore(directory: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AIUsageBar", isDirectory: true)) { [keys] create in try keys.get(create: create) }
    func loadPreferences() throws -> Preferences? {
        try files.load(Preferences.self, name: "preferences.sealed", legacyName: "preferences.json")
    }
    func loadCache() throws -> QuotaCache? {
        try files.load(QuotaCache.self, name: "quota-cache.sealed", legacyName: "snapshot.json")
    }
    func loadHistory() throws -> QuotaHistory? { try files.load(QuotaHistory.self, name: "quota-history.sealed") }
    func saveHistory(_ value: QuotaHistory) throws { try files.save(value, name: "quota-history.sealed") }
    func savePreferences(_ value: Preferences) throws { try files.save(value, name: "preferences.sealed") }
    func saveCache(_ value: QuotaCache) throws { try files.save(value, name: "quota-cache.sealed") }
}

private final class StorageKey {
    private var cached: SymmetricKey?
    func get(create: Bool) throws -> SymmetricKey {
        if let cached { return cached }
        // Exact app-owned item only. No provider Keychain search, export or synchronization.
        let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                      kSecAttrService as String: "io.github.EspressoTonic.ai-usage-bar.local-storage",
                                      kSecAttrAccount as String: "encryption-key-v1"]
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            let key = SymmetricKey(data: data); cached = key; return key
        }
        guard status == errSecItemNotFound, create else {
            throw BridgeError("Local encryption key is unavailable. Existing encrypted data has been preserved.")
        }
        let key = SymmetricKey(size: .bits256)
        var item = identity
        item[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        item[kSecAttrLabel as String] = "AI Usage Bar local encryption key"
        item[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        // The file-based macOS Keychain works with local ad-hoc builds. A nil trust list trusts only this app.
        var access: SecAccess?
        guard SecAccessCreate("AI Usage Bar local encryption key" as CFString, nil, &access) == errSecSuccess,
              let access else { throw BridgeError("Cannot configure local encryption key access.") }
        item[kSecAttrAccess as String] = access
        let added = SecItemAdd(item as CFDictionary, nil)
        if added == errSecDuplicateItem { return try get(create: false) }
        guard added == errSecSuccess else { throw BridgeError("Local encryption key could not be saved. No plaintext fallback was used.") }
        cached = key; return key
    }
}
