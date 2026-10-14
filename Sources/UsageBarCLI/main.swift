import Foundation
import UsageCore
import Darwin

func validClientID(_ value: String) -> Bool {
    !value.isEmpty && value.count <= 32 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
}
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "help"
if command == "help" || command == "--help" {
    print("""
    usagebar status                 Cached JSON snapshot from the running app
    usagebar refresh [provider]     Request background refresh
    usagebar select <chat-id>       Select an exact chat
    usagebar render --capture <id> Render a compact label for an optional display
    usagebar compact-captured <id> Compact that display's captured target
    usagebar compact <id> <revision> Compact an explicitly identified chat
    usagebar doctor                 Bridge compatibility and connection status
    """)
    exit(0)
}
do {
    var request = BridgeRequest(command: "status")
    switch command {
    case "refresh":
        if arguments.count > 1 && ProviderID(rawValue: arguments[1]) == nil { fail("Unknown provider.") }
        request = BridgeRequest(command: "refresh", provider: arguments.count > 1 ? ProviderID(rawValue: arguments[1]) : nil)
    case "select":
        guard arguments.count == 2 else { fail("usagebar select <chat-id>") }
        request = BridgeRequest(command: "select", chatID: arguments[1])
    case "compact":
        guard arguments.count == 3, let revision = Int(arguments[2]) else { fail("usagebar compact <chat-id> <selection-revision>") }
        request = BridgeRequest(command: "compact", chatID: arguments[1], selectionRevision: revision, requestID: UUID().uuidString)
    case "compact-captured":
        guard arguments.count == 2, validClientID(arguments[1]) else { fail("usagebar compact-captured <client-id>") }
        let capture = BridgePaths.directory.appendingPathComponent("captured-\(arguments[1]).json")
        let data = try Data(contentsOf: capture)
        guard data.count <= 8192 else { fail("Invalid captured display target.") }
        request = try JSONDecoder().decode(BridgeRequest.self, from: data)
        guard request.command == "compact" else { fail("Invalid captured command.") }
    case "render":
        guard arguments.count == 3, arguments[1] == "--capture", validClientID(arguments[2]) else { fail("usagebar render --capture <client-id>") }
    case "status", "doctor": break
    default: fail("Unknown command. Run usagebar --help.")
    }
    let response = try UnixBridgeClient.request(request)
    guard response.ok else { fail(response.message ?? "Request rejected.") }
    if command == "render" {
        if let snapshot = response.snapshot, let chat = snapshot.selectedChat {
            let target = BridgeRequest(command: "compact", chatID: chat.id, selectionRevision: snapshot.selectionRevision, requestID: UUID().uuidString)
            let url = BridgePaths.directory.appendingPathComponent("captured-\(arguments[2]).json")
            try JSONEncoder().encode(target).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let percent = chat.contextPercent.map { "\(Int($0))%" } ?? "—"
            let canCompact = CompactionGate.rejection(request: target, snapshot: snapshot) == nil
            print("\(String(chat.title.prefix(18))) · \(percent)\(canCompact ? " · Compact" : "")")
        } else { print("Choose a chat in AI Usage Bar") }
    } else if command == "doctor" {
        print("Bridge v\(response.version) · connected · \(response.snapshot?.sessions.count ?? 0) visible chats\(response.snapshot?.demo == true ? " · demo mode" : "")")
    } else {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(response), as: UTF8.self))
    }
} catch { fail(error.localizedDescription) }
