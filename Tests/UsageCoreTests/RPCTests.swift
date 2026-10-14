import Foundation
import Testing
@testable import UsageCore

struct RPCTests {
    @Test(arguments: ["after-ack", "before-ack", "busy"])
    func nativeCompactionRequiresMatchingCompletion(mode: String) async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/rpc_server.py")
        try await FixtureServer.withServer(script: fixture, mode: mode) { server in
            let rpc = CodexRPCClient()
            try await rpc.connect(endpoint: "ws://127.0.0.1:\(server.port)")
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
    }
    @Test func rejectsRemoteEndpointWithoutConnecting() async {
        let rpc = CodexRPCClient()
        for endpoint in ["ws://example.com:4500", "ws://example:password@127.0.0.1:4500",
                         "ws://127.0.0.1:4500?token=example", "ws://127.0.0.1:4500#secret"] {
            await #expect(throws: (any Error).self) { try await rpc.connect(endpoint: endpoint) }
        }
    }
}
