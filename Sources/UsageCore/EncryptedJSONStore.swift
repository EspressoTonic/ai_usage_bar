import Foundation
import CryptoKit

/// No plaintext fallback, embedded key, or key file. Tests inject disposable in-memory keys.
public final class EncryptedJSONStore {
    private let directory: URL
    private let key: (_ createIfMissing: Bool) throws -> SymmetricKey
    private let prefix = Data("AIUB1".utf8)
    public init(directory: URL, key: @escaping (_ createIfMissing: Bool) throws -> SymmetricKey) {
        self.directory = directory; self.key = key
    }
    public func load<T: Codable>(_ type: T.Type, name: String, legacyName: String? = nil) throws -> T? {
        if let bytes = try PrivateFiles.read(directory: directory, name: name) {
            guard bytes.starts(with: prefix) else { throw BridgeError("Encrypted storage format is invalid.") }
            let box = try AES.GCM.SealedBox(combined: bytes.dropFirst(prefix.count))
            let plaintext = try AES.GCM.open(box, using: key(false), authenticating: Data(name.utf8))
            let value = try JSONDecoder().decode(type, from: plaintext)
            // Finish cleanup if a prior migration stopped after the encrypted rename.
            if let legacyName { try PrivateFiles.remove(directory: directory, name: legacyName) }
            return value
        }
        guard let legacyName, let bytes = try PrivateFiles.read(directory: directory, name: legacyName) else { return nil }
        let value = try JSONDecoder().decode(type, from: bytes)
        // Re-encode the reduced model (not the original bytes), then remove the legacy file only after success.
        try save(value, name: name)
        try PrivateFiles.remove(directory: directory, name: legacyName)
        return value
    }
    public func save<T: Encodable>(_ value: T, name: String) throws {
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= 1_000_000 else { throw BridgeError("Encrypted storage exceeds its size limit.") }
        let box = try AES.GCM.seal(bytes, using: key(true), authenticating: Data(name.utf8))
        guard let combined = box.combined else { throw BridgeError("Encryption failed.") }
        try PrivateFiles.write(prefix + combined, directory: directory, name: name)
    }
}

/// Disk cache deliberately cannot encode chat labels, IDs, selections, operations or system history.
public struct QuotaCache: Codable, Equatable {
    public var schemaVersion = 1
    public var providers: [ProviderState]
    public init(providers: [ProviderState]) {
        self.providers = providers.map { state in
            guard state.id == .antigravity else { return state }
            var copy = state; copy.snapshot = nil; copy.error = nil; copy.refreshing = false
            return copy // Native usage reports do not establish account identity.
        }
    }
    public func restored(enabled: Set<ProviderID>) -> [ProviderState] {
        ProviderID.allCases.map { id in
            var copy = providers.first { $0.id == id } ?? ProviderState(id: id)
            copy.enabled = enabled.contains(id); copy.refreshing = false
            if !copy.enabled || id == .antigravity { copy.snapshot = nil; copy.error = nil; copy.nextAttempt = nil }
            else { copy.error = copy.snapshot == nil ? nil : "Previous reading · refresh to verify" }
            return copy
        }
    }
}
