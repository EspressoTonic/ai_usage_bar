import Foundation

public enum SessionMetadata {
    /// Consume bounded metadata chunks, not full transcript histories. No prompt text is retained.
    public static func parse(head: Data, tail: Data, modifiedAt: Date, fallbackTitle: String) -> ChatSession? {
        var id: String?
        var title = fallbackTitle
        var client = "Codex local"
        var model: String?
        var tokens: Int?
        var capacity: Int?
        var observed = modifiedAt
        var state: SessionRunState = .unknown
        for data in [head, tail] {
            for line in data.split(separator: 10) {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let type = json["type"] as? String, let payload = json["payload"] as? [String: Any] else { continue }
                if type == "session_meta" {
                    id = payload["id"] as? String
                    if let source = payload["source"] as? String { client = "Codex · " + source }
                    if let cwd = payload["cwd"] as? String { title = URL(fileURLWithPath: cwd).lastPathComponent }
                }
                if type == "turn_context" { model = payload["model"] as? String ?? model }
                if type == "event_msg" {
                    switch payload["type"] as? String {
                    case "task_started": state = .running
                    case "task_complete", "turn_aborted": state = .idle
                    case "token_count":
                        if let info = payload["info"] as? [String: Any] {
                            let last = info["last_token_usage"] as? [String: Any]
                            tokens = last?["total_tokens"] as? Int
                            capacity = info["model_context_window"] as? Int
                            if let stamp = json["timestamp"] as? String {
                                let formatter = ISO8601DateFormatter()
                                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                                observed = formatter.date(from: stamp) ?? ISO8601DateFormatter().date(from: stamp) ?? modifiedAt
                            }
                        }
                    default: break
                    }
                }
            }
        }
        guard let id else { return nil }
        return ChatSession(id: id, title: title.isEmpty ? "Untitled chat" : title, client: client, model: model,
                           tokens: tokens, capacity: capacity, observedAt: observed, runState: state)
    }
}

public actor SessionScanner {
    private var cache: [String: (Date, ChatSession)] = [:]
    public init() {}
    public func scan(root: URL, now: Date = Date()) -> [ChatSession] {
        let fm = FileManager.default
        var candidates: [(URL, Date)] = []
        // Bound directory discovery to the current and previous six days; older history is never walked.
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: -offset, to: now)!
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let day = root.appendingPathComponent(String(format: "%04d/%02d/%02d", parts.year!, parts.month!, parts.day!))
            for url in ((try? fm.contentsOfDirectory(at: day, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles])) ?? []).prefix(256) {
                guard url.pathExtension == "jsonl", let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      values.isRegularFile == true, let stamp = values.contentModificationDate else { continue }
                candidates.append((url, stamp))
            }
        }
        candidates.sort { $0.1 > $1.1 }
        var next: [String: (Date, ChatSession)] = [:]
        for (url, stamp) in candidates.prefix(32) {
            if let stored = cache[url.path], stored.0 == stamp { next[url.path] = stored; continue }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            do {
                let size = try handle.seekToEnd()
                try handle.seek(toOffset: 0)
                let head = try handle.read(upToCount: 16_384) ?? Data()
                try handle.seek(toOffset: size > 131_072 ? size - 131_072 : 0)
                let tail = try handle.read(upToCount: 131_072) ?? Data()
                if let session = SessionMetadata.parse(head: head, tail: tail, modifiedAt: stamp, fallbackTitle: "Local chat") {
                    next[url.path] = (stamp, session)
                }
            } catch { continue }
        }
        cache = next
        return next.values.map { $0.1 }.sorted { $0.observedAt > $1.observedAt }
    }
}
