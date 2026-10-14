import Foundation
import Testing
@testable import UsageCore

struct CoreTests {
    @Test func testCodexKeepsServerWindowDurationsAndMissingValuesUnknown() {
        let json: [String: Any] = ["rate_limit": [
            "primary_window": ["used_percent": 27.5, "limit_window_seconds": 900, "reset_at": 1_800_000_000],
            "secondary_window": ["used_percent": NSNull(), "limit_window_seconds": 604800]]]
        let windows = QuotaParser.codex(json)
        #expect(windows.count == 1)
        #expect(windows[0].label == "15 minutes")
        #expect(windows[0].remainingPercent == 72.5)
        #expect(windows[0].durationMinutes == 15)
    }
    @Test func testPercentRejectsBooleansAndOutOfRange() {
        for bad: Any in [true, -1, 101, Double.infinity, NSNull()] {
            #expect(QuotaParser.codex(["rate_limit": ["primary_window": ["used_percent": bad]]]).isEmpty)
        }
    }
    @Test func testClaudeDoesNotConfuseSpendWithQuota() {
        let windows = QuotaParser.claude(["five_hour": ["utilization": 12, "resets_at": "2026-10-14T18:00:00.123Z"],
                                         "seven_day_opus": ["utilization": 45], "extra_usage": ["used_credits": 900]])
        #expect(windows.count == 2)
        #expect(windows.first { $0.id == "five_hour" }?.resetsAt != nil)
        #expect(!windows.contains { $0.id == "extra_usage" })
    }
    @Test func testGeminiUsesMostConstrainedBucketForEachModel() {
        let windows = QuotaParser.gemini(["buckets": [
            ["modelId": "gemini-pro", "remainingFraction": 0.75],
            ["modelId": "gemini-pro", "remainingFraction": 0.35],
            ["modelId": "gemini-flash", "remainingFraction": 0.9],
            ["modelId": "missing", "remainingFraction": NSNull()]]])
        #expect(windows.count == 2)
        #expect(abs(windows.first { $0.id == "gemini-pro" }!.remainingPercent - 35) < 0.0001)
    }
    @Test func testMetadataUsesLastTurnRatherThanLifetimeUsage() {
        let head = Data("""
        {"type":"session_meta","payload":{"id":"chat-1","cwd":"/tmp/project","source":"cli"}}

        """.utf8)
        let tail = Data("""
        incomplete leading JSON
        {"type":"event_msg","timestamp":"2026-10-14T10:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":3000000},"last_token_usage":{"total_tokens":12000},"model_context_window":200000}}}
        {"type":"event_msg","payload":{"type":"task_complete"}}

        """.utf8)
        let chat = SessionMetadata.parse(head: head, tail: tail, modifiedAt: Date(), fallbackTitle: "fallback")!
        #expect(chat.tokens == 12000)
        #expect(chat.contextPercent == 6)
        #expect(chat.runState == .idle)
        #expect(!chat.nativeCompactionAvailable)
        #expect(chat.title == "project")
    }
    @Test func testMissingContextIsNotZeroAndStaleReadingDoesNotRecommend() {
        let unknown = ChatSession(id: "unknown", title: "Example", client: "CLI")
        #expect(unknown.contextPercent == nil)
        #expect(unknown.recommendation() == "Context measurement unavailable")
        let stale = ChatSession(id: "old", title: "Example", client: "CLI", tokens: 190, capacity: 200,
                                observedAt: Date().addingTimeInterval(-600))
        #expect(stale.recommendation() == "Old reading · refresh before deciding")
    }
    @Test func testCompactionRejectsSelectionRaceBusyAndUnverifiedSource() {
        var snapshot = AppSnapshot()
        snapshot.sessions = [ChatSession(id: "a", title: "Same title", client: "server", runState: .idle,
                                         source: .connectedServer, nativeCompactionAvailable: true)]
        snapshot.selectedChatID = "a"; snapshot.selectionRevision = 5
        let valid = BridgeRequest(command: "compact", chatID: "a", selectionRevision: 5, requestID: "operation")
        #expect(CompactionGate.rejection(request: valid, snapshot: snapshot) == nil)
        var moved = snapshot; moved.selectionRevision += 1
        #expect(CompactionGate.rejection(request: valid, snapshot: moved) != nil)
        var busy = snapshot; busy.sessions[0].runState = .running
        #expect(CompactionGate.rejection(request: valid, snapshot: busy) != nil)
        var local = snapshot; local.sessions[0].nativeCompactionAvailable = false
        #expect(CompactionGate.rejection(request: valid, snapshot: local) != nil)
        var demo = snapshot; demo.demo = true
        #expect(CompactionGate.rejection(request: valid, snapshot: demo) != nil)
    }
    @Test func testSnapshotRoundTripContainsNoCredentialFields() throws {
        var value = AppSnapshot()
        value.providers[0].snapshot = ProviderSnapshot(id: .codex, accountKey: "opaque", source: "test", windows: [])
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: data)
        #expect(value == decoded)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("access_token")); #expect(!text.contains("refresh_token"))
    }
    @Test func testUnixBridgeRoundTripAndSingleOwner() async throws {
        let parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("aiub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let path = parent.appendingPathComponent("test.sock").path
        let server = UnixBridgeServer(path: path) { request in BridgeResponse(ok: request.command == "status", snapshot: AppSnapshot()) }
        try server.start()
        defer { server.stop(); try? FileManager.default.removeItem(at: parent) }
        let response = try await Task.detached { try UnixBridgeClient.request(BridgeRequest(command: "status"), path: path) }.value
        #expect(response.ok); #expect(response.snapshot?.schemaVersion == 1)
        let second = UnixBridgeServer(path: path) { _ in BridgeResponse(ok: true) }
        #expect(throws: (any Error).self) { try second.start() }
        let again = try await Task.detached { try UnixBridgeClient.request(BridgeRequest(command: "status"), path: path) }.value
        #expect(again.ok)
    }
    @Test func testBridgeRejectsPublicDirectory() throws {
        let parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("aiub-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
        defer { try? FileManager.default.removeItem(at: parent) }
        let server = UnixBridgeServer(path: parent.appendingPathComponent("test.sock").path) { _ in BridgeResponse(ok: true) }
        #expect(throws: (any Error).self) { try server.start() }
    }
    @Test func testScannerCachesAndRestrictsRecentDirectories() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("aiub-scan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy/MM/dd"
        let day = root.appendingPathComponent(formatter.string(from: now))
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        let file = day.appendingPathComponent("rollout-example.jsonl")
        try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"recent\",\"source\":\"cli\"}}\n".utf8).write(to: file)
        let old = root.appendingPathComponent("2020/01/01")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"old\"}}\n".utf8).write(to: old.appendingPathComponent("old.jsonl"))
        let scanner = SessionScanner()
        let first = await scanner.scan(root: root, now: now)
        let second = await scanner.scan(root: root, now: now)
        #expect(first.map(\.id) == ["recent"]); #expect(first == second)
    }
}
