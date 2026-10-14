import Foundation

/// Connects only to a user-supplied existing local server. Never starts/resumes a chat to observe it.
public actor CodexRPCClient {
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var inUse = false
    private var nextID = 0
    private var completedCompactions: Set<String> = []
    private var contexts: [String: (Int?, Int?)] = [:]
    public init() {}
    public func connect(endpoint: String, bearer: String = "") async throws {
        guard !inUse else { throw BridgeError("Another app-server operation is in progress.") }
        inUse = true; defer { inUse = false }
        guard let url = URL(string: endpoint), url.scheme == "ws", ["127.0.0.1", "localhost", "::1"].contains(url.host ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw BridgeError("Use an existing local ws://127.0.0.1 app-server endpoint.")
        }
        disconnect()
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        var request = URLRequest(url: url)
        if !bearer.isEmpty { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 2_097_152
        self.session = session; self.socket = task; task.resume()
        _ = try await requestRPC("initialize", params: ["clientInfo": ["name": "ai_usage_bar", "version": "0.1.0"],
                                                         "capabilities": ["experimentalApi": false]])
        try await send(["method": "initialized"])
    }
    public func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil); session?.invalidateAndCancel()
        socket = nil; session = nil; contexts.removeAll(); completedCompactions.removeAll()
    }
    public func chats() async throws -> [ChatSession] {
        guard !inUse else { throw BridgeError("Another app-server operation is in progress.") }
        inUse = true; defer { inUse = false }
        let result = try await requestRPC("thread/list", params: ["limit": 32, "archived": false])
        return ((result["data"] as? [[String: Any]]) ?? []).compactMap { thread in
            guard let id = thread["id"] as? String else { return nil }
            let status = (thread["status"] as? [String: Any])?["type"] as? String
            let state: SessionRunState = status == "idle" ? .idle : status == "active" ? .running : .unknown
            return ChatSession(id: id, title: thread["name"] as? String ?? "Connected chat \(id.prefix(8))",
                               client: "Codex server", model: thread["model"] as? String,
                               tokens: contexts[id]?.0, capacity: contexts[id]?.1, runState: state,
                               source: .connectedServer, nativeCompactionAvailable: state == .idle)
        }
    }
    public func compact(chatID: String) async throws {
        guard !inUse else { throw BridgeError("Another app-server operation is in progress.") }
        inUse = true; defer { inUse = false }
        let read = try await requestRPC("thread/read", params: ["threadId": chatID, "includeTurns": false])
        guard let thread = read["thread"] as? [String: Any], thread["id"] as? String == chatID,
              (thread["status"] as? [String: Any])?["type"] as? String == "idle" else {
            throw BridgeError("The server cannot confirm that this exact chat is idle and loaded.")
        }
        completedCompactions.remove(chatID)
        _ = try await requestRPC("thread/compact/start", params: ["threadId": chatID])
        if completedCompactions.remove(chatID) != nil { return }
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            let message = try await receive(timeout: max(1, deadline.timeIntervalSinceNow))
            observe(message)
            let params = message["params"] as? [String: Any] ?? [:]
            if params["threadId"] as? String == chatID {
                if message["method"] as? String == "error" { throw BridgeError("The server reported a compaction failure.") }
                if message["method"] as? String == "item/completed",
                   (params["item"] as? [String: Any])?["type"] as? String == "contextCompaction" { return }
            }
        }
        throw BridgeError("Compaction completion was not observed. Check the chat before retrying.")
    }
    private func send(_ object: [String: Any]) async throws {
        guard let socket else { throw BridgeError("Connect to the existing app-server first.") }
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    private func requestRPC(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        nextID += 1; let id = nextID
        try await send(["method": method, "id": id, "params": params])
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let message = try await receive(timeout: max(0.1, deadline.timeIntervalSinceNow)); observe(message)
            if message["id"] as? Int == id {
                if message["error"] != nil { throw BridgeError("App-server rejected \(method). Verify this server's capabilities.") }
                return message["result"] as? [String: Any] ?? [:]
            }
        }
        throw BridgeError("App-server request timed out.")
    }
    private func receive(timeout: TimeInterval) async throws -> [String: Any] {
        guard let socket else { throw BridgeError("App-server is disconnected.") }
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                switch try await socket.receive() {
                case .data(let data): return data
                case .string(let string): return Data(string.utf8)
                @unknown default: throw BridgeError("Unsupported server message.")
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                socket.cancel(with: .goingAway, reason: nil)
                throw BridgeError("App-server timed out; connection closed.")
            }
            defer { group.cancelAll() }
            let data = try await group.next()!
            guard data.count <= 2_097_152, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw BridgeError("Invalid server response.")
            }
            return json
        }
    }
    private func observe(_ message: [String: Any]) {
        if message["method"] as? String == "item/completed",
           let params = message["params"] as? [String: Any], let id = params["threadId"] as? String,
           (params["item"] as? [String: Any])?["type"] as? String == "contextCompaction" {
            completedCompactions.insert(id)
            contexts.removeValue(forKey: id) // Pre-compaction usage is no longer current.
        }
        guard message["method"] as? String == "thread/tokenUsage/updated",
              let params = message["params"] as? [String: Any], let id = params["threadId"] as? String,
              let usage = params["tokenUsage"] as? [String: Any] else { return }
        let last = usage["last"] as? [String: Any]
        contexts[id] = (last?["totalTokens"] as? Int, usage["modelContextWindow"] as? Int)
    }
}
