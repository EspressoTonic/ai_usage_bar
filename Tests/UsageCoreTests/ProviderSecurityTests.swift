import Foundation
import Testing
import Darwin
@testable import UsageCore

struct ProviderSecurityTests {
    @Test func credentialsRejectUnsafeFilesWithoutChangingThem() throws {
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("aiub-credentials-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: directory) }
        // Provider directories need not be private; the credential file itself must be owner-only.
        let file = directory.appendingPathComponent("synthetic-sign-in")
        let contents = Data("{}".utf8)
        try contents.write(to: file); chmod(file.path, 0o600)
        #expect(try CredentialFile.read(file, maximum: 2) == contents)
        #expect(throws: (any Error).self) { _ = try CredentialFile.read(file, maximum: 1) }
        #expect(throws: (any Error).self) { _ = try CredentialFile.read(directory) }
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        #expect(throws: (any Error).self) { _ = try CredentialFile.read(link) }
        let fifo = directory.appendingPathComponent("pipe")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        let started = Date()
        #expect(throws: (any Error).self) { _ = try CredentialFile.read(fifo) }
        #expect(Date().timeIntervalSince(started) < 1)
        chmod(file.path, 0o644)
        #expect(throws: (any Error).self) { _ = try CredentialFile.read(file) }
        var info = stat(); #expect(lstat(file.path, &info) == 0 && info.st_mode & 0o777 == 0o644)
        #expect(try Data(contentsOf: file) == contents) // No automatic chmod, edits or deletion.
    }
    @Test func retryHeadersCannotCreateInfiniteOrUnboundedDelays() {
        #expect(RateLimitBackoff.delay(nil) == 120)
        for invalid in ["nan", "inf", "-inf", "invalid"] { #expect(RateLimitBackoff.delay(invalid) == 120) }
        #expect(RateLimitBackoff.delay("-10") == 30)
        #expect(RateLimitBackoff.delay("60") == 60)
        #expect(RateLimitBackoff.delay("999999999999999") == 86_400)
    }
    @Test(arguments: ["small", "exact-limit", "declared-limit", "stream-limit", "redirect", "auth-error", "cancel"])
    func streamedResponsesAreBoundedAndCancellable(mode: String) async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/http_server.py")
        try await FixtureServer.withServer(script: fixture, mode: mode) { server in
            let request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)/")!)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 2; configuration.timeoutIntervalForResource = 4
            if mode == "cancel" {
                let task = Task { try await BoundedHTTP.data(for: request, maximum: 64, configuration: configuration) }
                // Wait for the fixture to confirm it sent headers and the first chunk, rather than guessing timing.
                defer { task.cancel() }
                let bodyStarted = try await server.waitForBody()
                #expect(bodyStarted)
                let started = Date(); task.cancel()
                do { _ = try await task.value; #expect(Bool(false)) }
                catch { #expect(error is CancellationError) }
                #expect(Date().timeIntervalSince(started) < 1.5)
            } else if mode == "declared-limit" || mode == "stream-limit" {
                do { _ = try await BoundedHTTP.data(for: request, maximum: 64, configuration: configuration); #expect(Bool(false)) }
                catch {
                    #expect((error as? ProviderFailure)?.kind == .malformed)
                    #expect(!error.localizedDescription.contains("127.0.0.1"))
                }
            } else {
                let (data, http) = try await BoundedHTTP.data(for: request, maximum: 64, configuration: configuration)
                if mode == "redirect" { #expect(http.statusCode == 302 && data.isEmpty) }
                else if mode == "auth-error" { #expect(http.statusCode == 401 && data.isEmpty) }
                else if mode == "exact-limit" { #expect(data.count == 64 && http.statusCode == 200) }
                else { #expect(data == Data("{\"ok\":true}".utf8) && http.statusCode == 200) }
            }
        }
    }
}
