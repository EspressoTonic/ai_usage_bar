import Foundation
import Testing
import CryptoKit
import Darwin
@testable import UsageCore

struct SecurityTests {
    private func scratch() -> URL {
        URL(fileURLWithPath: "/private/tmp").appendingPathComponent("aiub-security-" + UUID().uuidString)
    }
    @Test func encryptedStorageRejectsTamperingWrongKeyAndWrongFile() throws {
        let directory = scratch(); defer { try? FileManager.default.removeItem(at: directory) }
        let key = SymmetricKey(size: .bits256)
        let store = EncryptedJSONStore(directory: directory) { _ in key }
        let value = ["project": "private-project", "path": "/Users/example/private"]
        try store.save(value, name: "preferences.sealed")
        let decoded = try store.load([String: String].self, name: "preferences.sealed")
        #expect(decoded == value)
        let storedBytes = try PrivateFiles.read(directory: directory, name: "preferences.sealed")
        let bytes = try #require(storedBytes)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("private-project"))
        let wrong = EncryptedJSONStore(directory: directory) { _ in SymmetricKey(size: .bits256) }
        #expect(throws: (any Error).self) { _ = try wrong.load([String: String].self, name: "preferences.sealed") }
        try PrivateFiles.write(bytes, directory: directory, name: "other.sealed")
        #expect(throws: (any Error).self) { _ = try store.load([String: String].self, name: "other.sealed") }
        var tampered = bytes; tampered[tampered.count - 1] ^= 1
        try PrivateFiles.write(tampered, directory: directory, name: "preferences.sealed")
        #expect(throws: (any Error).self) { _ = try store.load([String: String].self, name: "preferences.sealed") }
    }
    @Test func migrationMinimizesChatDataAndPreservesPlaintextIfKeyFails() throws {
        let directory = scratch(); defer { try? FileManager.default.removeItem(at: directory) }
        var original = AppSnapshot()
        original.sessions = [ChatSession(id: "private-id", title: "private-title", client: "cli")]
        original.selectedChatID = "private-id"
        try PrivateFiles.write(JSONEncoder().encode(original), directory: directory, name: "snapshot.json")
        let unavailable = EncryptedJSONStore(directory: directory) { _ in throw BridgeError("Key unavailable") }
        #expect(throws: (any Error).self) { _ = try unavailable.load(QuotaCache.self, name: "quota-cache.sealed", legacyName: "snapshot.json") }
        #expect(try PrivateFiles.read(directory: directory, name: "snapshot.json") != nil)
        #expect(try PrivateFiles.read(directory: directory, name: "quota-cache.sealed") == nil)
        let key = SymmetricKey(size: .bits256)
        let store = EncryptedJSONStore(directory: directory) { _ in key }
        let loadedCache = try store.load(QuotaCache.self, name: "quota-cache.sealed", legacyName: "snapshot.json")
        let cache = try #require(loadedCache)
        #expect(cache.providers == original.providers)
        let text = String(decoding: try JSONEncoder().encode(cache), as: UTF8.self)
        #expect(!text.contains("private-id") && !text.contains("private-title") && !text.contains("sessions"))
        #expect(try PrivateFiles.read(directory: directory, name: "snapshot.json") == nil)
        // Loading an existing ciphertext may not generate a replacement key.
        let missing = EncryptedJSONStore(directory: directory) { create in
            #expect(!create); throw BridgeError("Key missing")
        }
        #expect(throws: (any Error).self) { _ = try missing.load(QuotaCache.self, name: "quota-cache.sealed") }
    }
    @Test func privateFilesRejectSymlinksPublicPermissionsAndOversize() throws {
        let directory = scratch(); defer { try? FileManager.default.removeItem(at: directory) }
        try PrivateFiles.write(Data("safe".utf8), directory: directory, name: "original")
        var info = stat(); #expect(lstat(directory.appendingPathComponent("original").path, &info) == 0)
        #expect(info.st_mode & 0o777 == 0o600)
        try FileManager.default.createSymbolicLink(atPath: directory.appendingPathComponent("link").path,
                                                   withDestinationPath: "original")
        #expect(throws: (any Error).self) { _ = try PrivateFiles.read(directory: directory, name: "link") }
        // Saving atomically replaces a symlink, leaving its target untouched.
        try PrivateFiles.write(Data("new".utf8), directory: directory, name: "link")
        #expect(try PrivateFiles.read(directory: directory, name: "original") == Data("safe".utf8))
        #expect(throws: (any Error).self) { _ = try PrivateFiles.read(directory: directory, name: "original", maximum: 2) }
        #expect(throws: (any Error).self) { try PrivateFiles.write(Data(), directory: directory, name: "../escape") }
        chmod(directory.appendingPathComponent("original").path, 0o644)
        #expect(throws: (any Error).self) { _ = try PrivateFiles.read(directory: directory, name: "original") }
        chmod(directory.path, 0o755)
        #expect(throws: (any Error).self) { try PrivateFiles.write(Data(), directory: directory, name: "test") }
    }
    @Test func bridgePrivacyRequiresExplicitChatAccess() throws {
        var snapshot = AppSnapshot()
        snapshot.sessions = [ChatSession(id: "private-id", title: "private-title", client: "cli")]
        snapshot.selectedChatID = "private-id"; snapshot.selectionRevision = 7
        snapshot.operation = CompactionOperation(id: "request", chatID: "private-id", state: "running", message: "Waiting")
        snapshot.providers[0].snapshot = ProviderSnapshot(id: .codex, accountKey: "private-account", source: "CLI", windows: [])
        #expect(BridgePrivacy.rejection(command: "compact", allowChatAccess: false) != nil)
        #expect(BridgePrivacy.rejection(command: "select", allowChatAccess: false) != nil)
        #expect(BridgePrivacy.rejection(command: "status", allowChatAccess: false) == nil)
        #expect(BridgePrivacy.rejection(command: "compact", allowChatAccess: true) == nil)
        let publicView = BridgePrivacy.snapshot(snapshot, allowChatAccess: false)
        #expect(publicView.sessions.isEmpty && publicView.selectedChatID == nil && publicView.operation == nil)
        let text = String(decoding: try JSONEncoder().encode(publicView), as: UTF8.self)
        #expect(!text.contains("private-id") && !text.contains("private-title") && !text.contains("private-account"))
        #expect(BridgePrivacy.snapshot(snapshot, allowChatAccess: true).selectedChatID == "private-id")
        #expect(snapshot.providers[0].snapshot?.accountKey == "private-account")
    }
    @Test func capturedTargetsExpireAndRejectFutureTimestamps() throws {
        let now = Date()
        let request = BridgeRequest(command: "compact", chatID: "chat", selectionRevision: 3, requestID: "request")
        #expect(try CapturedAction(request: request, createdAt: now).validate(at: now).chatID == "chat")
        #expect(throws: (any Error).self) { _ = try CapturedAction(request: request, createdAt: now.addingTimeInterval(-31)).validate(at: now) }
        #expect(throws: (any Error).self) { _ = try CapturedAction(request: request, createdAt: now.addingTimeInterval(10)).validate(at: now) }
        #expect(throws: (any Error).self) { _ = try CapturedAction(request: BridgeRequest(command: "refresh")).validate() }
    }
    @Test func providerRedirectsNeverReceiveAuthorization() {
        var next: URLRequest? = URLRequest(url: URL(string: "https://untrusted.example")!)
        let url = URL(string: "https://chatgpt.com")!
        let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
        let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
        NoRedirects().urlSession(session, task: session.dataTask(with: url), willPerformHTTPRedirection: response,
                                newRequest: next!) { next = $0 }
        #expect(next == nil)
    }
}
