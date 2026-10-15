import Foundation
import Testing
import Darwin
@testable import UsageCore

struct QuotaDetailsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func reading(used: Double = 20, account: String = "invented", captured: Date? = nil, reset: Date? = nil) -> ProviderSnapshot {
        var value = ProviderSnapshot(id: .codex, accountKey: account, source: "fixture", capturedAt: captured ?? now,
            windows: [QuotaWindow(id: "session", label: "5 hours", usedPercent: used, resetsAt: reset ?? now.addingTimeInterval(7200), durationMinutes: 300)])
        value.identityVerified = true; return value
    }
    @Test func paceRequiresFreshKnownWindowAndSuppressesEarlyOrInvalidData() {
        let sample = reading(used: 50)
        let estimate = QuotaPace.estimate(window: sample.windows[0], capturedAt: now, now: now)
        #expect(estimate?.aheadOfTime == false)
        #expect(estimate?.exhaustionAt == nil)
        var window = sample.windows[0]; window.usedPercent = 80
        #expect(QuotaPace.estimate(window: window, capturedAt: now, now: now)?.exhaustionAt == now.addingTimeInterval(2700))
        #expect(QuotaPace.estimate(window: window, capturedAt: now, now: now.addingTimeInterval(601)) == nil)
        #expect(QuotaPace.estimate(window: window, capturedAt: now, now: now.addingTimeInterval(-1)) == nil)
        window.durationMinutes = nil
        #expect(QuotaPace.estimate(window: window, capturedAt: now, now: now) == nil)
        window.durationMinutes = 300; window.resetsAt = now.addingTimeInterval(17999)
        #expect(QuotaPace.estimate(window: window, capturedAt: now, now: now) == nil)
        window.resetsAt = now.addingTimeInterval(18001)
        #expect(QuotaPace.estimate(window: window, capturedAt: now, now: now) == nil)
        window.resetsAt = now; window.usedPercent = .nan
        #expect(QuotaPace.estimate(window: window, capturedAt: now, now: now) == nil)
    }
    @Test func historyIsBoundedAndNeverCombinesAccountsOrResetCycles() {
        var history = QuotaHistory()
        let cycleReset = now.addingTimeInterval(120000)
        for index in 0..<1100 {
            let time = now.addingTimeInterval(Double(index) * 60)
            history.record(source: "source", reading: reading(used: Double(index % 100), captured: time, reset: cycleReset), now: time)
        }
        #expect(history.points.count == 1000)
        let last = now.addingTimeInterval(1100 * 60)
        history.record(source: "other-source", reading: reading(account: "other", captured: last, reset: cycleReset), now: last)
        #expect(history.series(source: "other-source", account: "other", window: reading(reset: cycleReset).windows[0]).count == 1)
        #expect(history.series(source: "source", account: "other", window: reading().windows[0]).isEmpty)
        var newCycle = reading().windows[0]; newCycle.resetsAt = now.addingTimeInterval(20000)
        #expect(history.series(source: "source", account: "invented", window: newCycle).isEmpty)
        let count = history.points.count
        var unknown = reading(captured: last, reset: cycleReset); unknown.identityVerified = false
        history.record(source: "unknown", reading: unknown, now: last)
        unknown.id = .antigravity; unknown.identityVerified = true
        history.record(source: "unknown", reading: unknown, now: last)
        #expect(history.points.count == count)
        var noReset = reading(captured: last, reset: cycleReset); noReset.windows[0].resetsAt = nil
        history.record(source: "missing-reset", reading: noReset, now: last)
        #expect(history.points.count == count)
        history.prune(now: last.addingTimeInterval(8 * 86400))
        #expect(history.points.isEmpty)
    }
    @Test func alertsAreSilentInitiallyDeduplicateAndRequireObservedTransitions() {
        var tracker = QuotaAlertTracker()
        #expect(tracker.observe(source: "a", reading: reading(used: 80), threshold: 10, now: now).isEmpty)
        let low = reading(used: 91, captured: now.addingTimeInterval(1))
        #expect(tracker.observe(source: "a", reading: low, threshold: 10, now: low.capturedAt) == [.low])
        var later = low; later.capturedAt = now.addingTimeInterval(2)
        #expect(tracker.observe(source: "a", reading: later, threshold: 10, now: later.capturedAt).isEmpty)
        #expect(tracker.observe(source: "b", reading: low, threshold: 10, now: low.capturedAt).isEmpty)
        later.accountKey = "other-account"; later.capturedAt = now.addingTimeInterval(3)
        #expect(tracker.observe(source: "a", reading: later, threshold: 10, now: later.capturedAt).isEmpty)
        let reset = reading(used: 0, captured: now.addingTimeInterval(7201), reset: now.addingTimeInterval(25200))
        #expect(tracker.observe(source: "a", reading: reset, threshold: 10, now: reset.capturedAt) == [.reset])
        #expect(tracker.observe(source: "a", reading: reset, threshold: 10, now: reset.capturedAt).isEmpty)
        var unknown = reading(used: 100); unknown.identityVerified = false
        #expect(tracker.observe(source: "a", reading: unknown, threshold: 10, now: now).isEmpty)
        #expect(tracker.observe(source: "a", reading: low, threshold: 10, now: now.addingTimeInterval(1000)).isEmpty)
    }
    @Test func menuQuotaNeverUsesDisabledStaleOrUnrelatedWindows() {
        let selection = MenuQuotaSelection(source: "codex", window: "session")
        var state = ProviderState(id: .codex, enabled: true); state.snapshot = reading(used: 28)
        #expect(selection.percentage(in: state, now: now) == 72)
        #expect(selection.percentage(in: state, now: now.addingTimeInterval(601)) == nil)
        state.error = "Previous reading"; #expect(selection.percentage(in: state, now: now) == nil)
        state.error = nil; state.enabled = false; #expect(selection.percentage(in: state, now: now) == nil)
        state.enabled = true; state.snapshot?.windows[0].id = "different"
        #expect(selection.percentage(in: state, now: now) == nil)
    }
    @Test func nativeParserPrefersBucketsPreservesUnknownsAndCredits() throws {
        let account: [String: Any] = ["type": "chatgpt", "email": "invented@example.test", "planType": "pro"]
        let limits: [String: Any] = ["accountId": "invented-workspace", "rateLimits": ["primary": ["usedPercent": 99]],
            "rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 25, "windowDurationMins": 300],
                "secondary": ["usedPercent": true], "credits": ["balance": "12.5", "unlimited": false]],
                "other": ["primary": ["usedPercent": 50]]], "rateLimitResetCredits": ["availableCount": 2]]
        let result = try CodexQuotaExchange.parse(account: account, limits: limits, binding: "source")
        #expect(result.windows.count == 2 && result.windows[0].usedPercent == 25)
        #expect(result.windows[1].durationMinutes == nil && result.windows[1].resetsAt == nil)
        #expect(result.identityVerified == true && result.identity?.email == "invented@example.test")
        #expect(result.credits?.first?.balance == "12.5" && result.credits?.last?.resetCredits == 2)
        let other = try CodexQuotaExchange.parse(account: account, limits: limits, binding: "different-source")
        #expect(other.accountKey != result.accountKey)
        let legacy = try CodexQuotaExchange.parse(account: account, limits: ["rateLimits": ["primary": ["usedPercent": 0]]], binding: "source")
        #expect(legacy.identityVerified == false && legacy.windows[0].usedPercent == 0)
        #expect(QuotaDetails.credits(["balance": "secret text", "unlimited": 1], id: "a", label: "a") == nil)
    }
    @Test func profileConfigurationRejectsOptionsAndQuotesRemotePaths() throws {
        var profile = CodexProfile(label: "Work", location: .ssh, host: "my-server", home: "/home/example/a'$(touch sentinel)", executable: "/home/example/bin/codex")
        let arguments = try profile.sshArguments()
        #expect(arguments.contains("BatchMode=yes") && arguments.contains("StrictHostKeyChecking=yes"))
        #expect(arguments[arguments.count - 2] == "my-server")
        #expect(arguments.last?.contains("'\"'\"'") == true)
        profile.host = "-oProxyCommand=bad"
        #expect(throws: (any Error).self) { _ = try profile.sshArguments() }
        profile.host = "ok"; profile.home = "relative"
        #expect(throws: (any Error).self) { try profile.validate() }
        profile.home = "/home/example"; profile.label = "Bad\nlabel"
        #expect(throws: (any Error).self) { try profile.validate() }
    }
    @Test func remoteCommandTreatsShellSyntaxAsLiteralPaths() async throws {
        try await fixture(mode: "success") { _, root in
            let executable = root.appendingPathComponent("codex '$(touch SENTINEL)")
            try Data("#!/bin/sh\nprintf '%s\\n' \"$CODEX_HOME\" \"$1\"\n".utf8).write(to: executable); chmod(executable.path, 0o700)
            let home = root.path + "/home '$(touch SENTINEL)"
            let profile = CodexProfile(label: "Fixture", location: .ssh, host: "fixture", home: home, executable: executable.path)
            let arguments = try profile.sshArguments()
            let result = try await CommandProbe.run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", arguments.last!],
                environment: ["PATH": "/usr/bin:/bin"], directory: root, timeout: 3)
            #expect(result.status == 0)
            #expect(String(decoding: result.stdout, as: UTF8.self) == home + "\napp-server\n")
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("SENTINEL").path))
        }
    }
    @Test func nativeSourceRejectsSymlinkHomesAndOtherWritableParents() async throws {
        try await fixture(mode: "success") { profile, root in
            let link = root.appendingPathComponent("linked-home")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: profile.home)
            var changed = profile; changed.home = link.path
            do { _ = try await CodexQuotaClient().fetch(profile: changed); #expect(Bool(false)) }
            catch { #expect((error as? ProviderFailure)?.kind == .configuration) }
            let parent = root.appendingPathComponent("unsafe")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            chmod(parent.path, 0o777)
            #expect(throws: (any Error).self) { try CodexQuotaClient.trustedParents(of: parent.appendingPathComponent("codex")) }
        }
    }
    @Test func metadataRedactionAndOldSnapshotDecodingRemainCompatible() throws {
        var snapshot = AppSnapshot(); var state = ProviderState(id: .codex, enabled: true)
        state.snapshot = reading(); state.snapshot?.identity = AccountIdentity(email: "invented@example.test", workspace: "Synthetic team")
        snapshot.providers = [state]
        snapshot.codexProfiles = [CodexProfileState(profile: CodexProfile(label: "Private source"))]
        let redacted = BridgePrivacy.snapshot(snapshot, allowChatAccess: true)
        let encoded = try JSONEncoder().encode(redacted)
        #expect(redacted.codexProfiles == nil && redacted.providers[0].snapshot?.identity == nil)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("invented@example.test"))
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        object.removeValue(forKey: "codexProfiles")
        let old = try JSONDecoder().decode(AppSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(old.codexProfiles == nil)
    }
    @Test(arguments: ["success", "missing-identity", "rotation", "signed-out", "bad-json", "error", "wrong-id", "overflow", "group"])
    func nativeReaderUsesReadOnlyHandshakeAndCleansUp(mode: String) async throws {
        try await fixture(mode: mode) { profile, root in
            do {
                let result = try await CodexQuotaClient().fetch(profile: profile)
                #expect(["success", "missing-identity", "group"].contains(mode))
                #expect(result.windows.count == 1 && result.identity?.email == "person@example.test")
                #expect(result.credits?.first(where: { $0.resetCredits != nil })?.resetCredits == 2)
                #expect(result.identityVerified == (mode != "missing-identity"))
                if mode == "group" {
                    let marker = root.appendingPathComponent("heartbeat")
                    let first = try Data(contentsOf: marker)
                    try await Task.sleep(nanoseconds: 150_000_000)
                    #expect(try Data(contentsOf: marker) == first)
                }
            } catch {
                #expect(!["success", "missing-identity", "group"].contains(mode))
                let kind = (error as? ProviderFailure)?.kind
                if ["rotation", "signed-out"].contains(mode) { #expect(kind == .authentication) }
                if ["bad-json", "wrong-id", "overflow"].contains(mode) { #expect(kind == .malformed) }
                if mode == "error" { #expect(kind == .unsupported) }
                #expect(!error.localizedDescription.contains("SYNTHETIC-PRIVATE"))
            }
        }
    }
    @Test(arguments: ["timeout", "cancel"])
    func nativeDialogueHonorsDeadlineAndCancellation(mode: String) async throws {
        try await fixture(mode: mode) { profile, root in
            let exchange = CodexQuotaExchange(binding: profile.binding)
            var environment = CodexQuotaClient.environment(directory: root); environment["CODEX_HOME"] = profile.home
            let task = Task { try await CommandProbe.run(executable: URL(fileURLWithPath: profile.executable), arguments: ["app-server"],
                environment: environment, directory: root, timeout: mode == "timeout" ? 0.4 : 8, dialogue: try exchange.dialogue()) }
            if mode == "cancel" {
                for _ in 0..<240 {
                    if FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path) { break }
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("ready").path)); task.cancel()
            }
            do { _ = try await task.value; #expect(Bool(false)) }
            catch { #expect(mode != "cancel" || error is CancellationError) }
        }
    }
    private func fixture<T>(mode: String, _ action: (CodexProfile, URL) async throws -> T) async throws -> T {
        try await FixtureProcessBudget.shared.run {
            let root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("aiub-codex-test-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: root) }
            let home = root.appendingPathComponent("home")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/codex_quota_fixture.py")
            let executable = root.appendingPathComponent("codex-" + mode)
            try FileManager.default.copyItem(at: script, to: executable); chmod(executable.path, 0o700)
            return try await action(CodexProfile(label: "Fixture", home: home.path, executable: executable.path), root)
        }
    }
}
