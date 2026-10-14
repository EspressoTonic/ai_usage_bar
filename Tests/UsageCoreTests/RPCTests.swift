import Foundation
import Testing
@testable import UsageCore

struct RPCTests {
    @Test(arguments: ["after-ack", "before-ack", "busy"])
    func nativeCompactionRequiresMatchingCompletion(mode: String) async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/rpc_server.py")
        let process = Process(); let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", fixture.path, mode]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() }; process.waitUntilExit() }
        let line = output.fileHandleForReading.availableData
        let port = try #require(Int(String(decoding: line, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let rpc = CodexRPCClient()
        try await rpc.connect(endpoint: "ws://127.0.0.1:\(port)")
        let chats = try await rpc.chats()
        #expect(chats.count == 1); #expect(chats[0].id == "fixture-chat")
        let started = Date()
        if mode == "busy" {
            await #expect(throws: (any Error).self) { try await rpc.compact(chatID: "fixture-chat") }
        } else {
            try await rpc.compact(chatID: "fixture-chat")
            if mode == "after-ack" { #expect(Date().timeIntervalSince(started) >= 0.25) }
        }
        await rpc.disconnect()
    }
    @Test func rejectsRemoteEndpointWithoutConnecting() async {
        let rpc = CodexRPCClient()
        await #expect(throws: (any Error).self) { try await rpc.connect(endpoint: "ws://example.com:4500") }
    }
}
