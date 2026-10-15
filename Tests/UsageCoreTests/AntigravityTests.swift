import Foundation
import Testing
import Darwin
@testable import UsageCore

struct AntigravityTests {
    private func report(_ buckets: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": "SUCCESS", "command": ["name": "usage", "data": ["groups": [
            ["display_name": "Gemini Models", "buckets": buckets]]]]])
    }
    @Test func reportsOnlyMeasuredEnabledLimits() throws {
        let windows = try AntigravityClient.windows(report([
            ["display_name": "Weekly", "remaining_fraction": 0.6, "reset_time": "2026-10-19T12:00:00Z"],
            ["displayName": "5 hours", "remaining": ["case": "remainingFraction", "value": 0.8]],
            ["display_name": "Disabled", "disabled": true, "remaining_fraction": 1],
            ["display_name": "Missing", "reset_time": "2026-10-19T12:00:00Z"],
            ["display_name": "Boolean", "remaining_fraction": true],
            ["display_name": "Invalid", "remaining_fraction": 1.1]]))
        #expect(windows.count == 2)
        #expect(abs(windows[0].remainingPercent - 60) < 0.001)
        #expect(windows[0].durationMinutes == 10080 && windows[0].resetsAt != nil)
        #expect(abs(windows[1].remainingPercent - 80) < 0.001)
        #expect(windows[1].durationMinutes == 300)
        #expect(throws: (any Error).self) { _ = try AntigravityClient.windows(report([["remaining_fraction": false]])) }
        #expect(throws: (any Error).self) { _ = try AntigravityClient.windows(Data("{\"status\":\"SUCCESS\",\"response\":\"model answer\"}".utf8)) }
    }
    @Test func weeklyOnlyAndCamelCaseRemainDistinct() throws {
        let weekly = try AntigravityClient.windows(report([["displayName": "Weekly", "remainingFraction": 1.0, "disabled": false]]))
        #expect(weekly.count == 1 && weekly[0].durationMinutes == 10080 && weekly[0].remainingPercent == 100)
        #expect(ProviderID.gemini.title == "Gemini CLI")
        #expect(ProviderID.antigravity.credentialRelativePath == ".local/bin/agy")
        #expect(AntigravityClient.supportsUsageReport(Data("1.3.5\n".utf8)))
        #expect(!AntigravityClient.supportsUsageReport(Data("1.1.10".utf8)))
        #expect(!AntigravityClient.supportsUsageReport(Data("unknown 1.3.5".utf8)))
    }
    @Test func cacheUpgradeAddsNewProviderWithoutRestoringUnverifiedAccount() {
        var original = ProviderState(id: .codex, enabled: true)
        original.snapshot = ProviderSnapshot(id: .codex, accountKey: "synthetic", source: "fixture", windows: [])
        let oldCache = QuotaCache(providers: [original, ProviderState(id: .claude), ProviderState(id: .gemini)])
        let restored = oldCache.restored(enabled: [.codex])
        #expect(restored.count == ProviderID.allCases.count)
        #expect(restored.first { $0.id == .antigravity }?.enabled == false)
        #expect(restored.first { $0.id == .codex }?.snapshot != nil)
        var unverified = ProviderState(id: .antigravity, enabled: true)
        unverified.snapshot = ProviderSnapshot(id: .antigravity, accountKey: "unverified", source: "fixture", windows: [])
        let cache = QuotaCache(providers: [unverified])
        #expect(cache.providers[0].snapshot == nil)
        #expect(cache.restored(enabled: [.antigravity]).first { $0.id == .antigravity }?.snapshot == nil)
    }
    @Test(arguments: ["success", "old", "signin", "bad-report", "environment"])
    func nativeReportUsesTheConfiguredExecutable(mode: String) async throws {
        try await fixture(mode: mode) { executable, work in
            do {
                let reading = try await AntigravityClient().fetch(executableURL: executable)
                #expect(mode == "success" || mode == "environment")
                #expect(reading.id == .antigravity && reading.windows.count == 3)
                #expect(reading.source.contains("account identity not supplied"))
            } catch {
                #expect(mode == "old" || mode == "signin" || mode == "bad-report")
                #expect(error is ProviderFailure)
                #expect(!error.localizedDescription.contains("SYNTHETIC-PRIVATE"))
            }
            #expect(!FileManager.default.fileExists(atPath: work.appendingPathComponent("unexpected-usage").path))
        }
    }
    @Test(arguments: ["overflow", "timeout", "cancel", "group"])
    func subprocessLimitsCancellationAndGroupCleanup(mode: String) async throws {
        try await fixture(mode: mode) { executable, work in
            let environment = try AntigravityClient.environment(directory: work)
            let task = Task { try await CommandProbe.run(executable: executable, arguments: ["-p", "/usage", "--output-format", "json"],
                environment: environment, directory: work, timeout: mode == "timeout" ? 0.3 : (mode == "cancel" ? 8 : 4), maximum: 4096) }
            if mode == "cancel" {
                for _ in 0..<240 {
                    if FileManager.default.fileExists(atPath: work.appendingPathComponent("ready").path) { break }
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                #expect(FileManager.default.fileExists(atPath: work.appendingPathComponent("ready").path))
                task.cancel()
            }
            do {
                _ = try await task.value
                #expect(mode == "group")
                if mode == "group" {
                    let marker = work.appendingPathComponent("heartbeat")
                    let first = try Data(contentsOf: marker)
                    try await Task.sleep(nanoseconds: 200_000_000)
                    #expect(try Data(contentsOf: marker) == first)
                }
            } catch {
                #expect(mode != "group")
                if mode == "cancel" { #expect(error is CancellationError) }
                #expect(!error.localizedDescription.contains("SYNTHETIC-PRIVATE"))
            }
        }
    }
    private func fixture<T>(mode: String, _ action: (URL, URL) async throws -> T) async throws -> T {
        let work = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("aiub-agy-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: work) }
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/agy_fixture.py")
        let executable = work.appendingPathComponent("agy-" + mode)
        try FileManager.default.copyItem(at: script, to: executable); chmod(executable.path, 0o700)
        return try await action(executable, work)
    }
}
