import Foundation

public enum ProviderID: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex, claude, gemini, antigravity
    public var id: String { rawValue }
    public var title: String { self == .gemini ? "Gemini CLI" : rawValue.capitalized }
    public var symbol: String {
        switch self { case .codex: return "terminal"; case .claude: return "sparkle"; case .gemini: return "diamond"; case .antigravity: return "sparkles" }
    }
    public var credentialRelativePath: String {
        switch self {
        case .codex: return ".codex/auth.json"
        case .claude: return ".claude/.credentials.json"
        case .gemini: return ".gemini/oauth_creds.json"
        case .antigravity: return ".local/bin/agy" // Executable path; credentials remain inside agy.
        }
    }
}

public struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public var durationMinutes: Int?
    public var remainingPercent: Double { max(0, 100 - usedPercent) }
    public init(id: String, label: String, usedPercent: Double, resetsAt: Date? = nil, durationMinutes: Int? = nil) {
        self.id = id; self.label = label; self.usedPercent = usedPercent
        self.resetsAt = resetsAt; self.durationMinutes = durationMinutes
    }
}

public struct ProviderSnapshot: Codable, Equatable, Sendable, Identifiable {
    public var id: ProviderID
    public var accountKey: String
    public var source: String
    public var capturedAt: Date
    public var windows: [QuotaWindow]
    public init(id: ProviderID, accountKey: String, source: String, capturedAt: Date = Date(), windows: [QuotaWindow]) {
        self.id = id; self.accountKey = accountKey; self.source = source
        self.capturedAt = capturedAt; self.windows = windows
    }
}

public struct ProviderState: Codable, Equatable, Identifiable, Sendable {
    public var id: ProviderID
    public var enabled: Bool
    public var snapshot: ProviderSnapshot?
    public var refreshing = false
    public var error: String?
    public var lastAttempt: Date?
    public var nextAttempt: Date?
    public init(id: ProviderID, enabled: Bool = false) { self.id = id; self.enabled = enabled }
}

public enum SessionRunState: String, Codable, Sendable { case idle, running, unknown }
public enum SessionSource: String, Codable, Sendable { case localMetadata, connectedServer, demo }

public struct ChatSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var client: String
    public var model: String?
    public var tokens: Int?
    public var capacity: Int?
    public var observedAt: Date
    public var runState: SessionRunState
    public var source: SessionSource
    public var nativeCompactionAvailable: Bool
    public var contextPercent: Double? {
        guard let tokens, let capacity, tokens >= 0, capacity > 0 else { return nil }
        return min(100, Double(tokens) / Double(capacity) * 100)
    }
    public init(id: String, title: String, client: String, model: String? = nil, tokens: Int? = nil,
                capacity: Int? = nil, observedAt: Date = Date(), runState: SessionRunState = .unknown,
                source: SessionSource = .localMetadata, nativeCompactionAvailable: Bool = false) {
        self.id = id; self.title = title; self.client = client; self.model = model
        self.tokens = tokens; self.capacity = capacity; self.observedAt = observedAt
        self.runState = runState; self.source = source; self.nativeCompactionAvailable = nativeCompactionAvailable
    }
    public func recommendation(at now: Date = Date(), threshold: Double = 80) -> String {
        guard now.timeIntervalSince(observedAt) < 300 else { return "Old reading · refresh before deciding" }
        guard let percent = contextPercent else { return "Context measurement unavailable" }
        if percent >= threshold {
            return runState == .running ? "Consider a checkpoint after this turn" : "Consider a checkpoint before continuing"
        }
        return "Room to continue"
    }
}

public struct SystemMetrics: Codable, Equatable, Sendable {
    public var cpuPercent: Double?
    public var memoryUsedBytes: UInt64
    public var memoryTotalBytes: UInt64
    public var appResidentBytes: UInt64
    public var pressure: String
    public var capturedAt: Date
    public init(cpuPercent: Double?, memoryUsedBytes: UInt64, memoryTotalBytes: UInt64,
                appResidentBytes: UInt64, pressure: String, capturedAt: Date = Date()) {
        self.cpuPercent = cpuPercent; self.memoryUsedBytes = memoryUsedBytes; self.memoryTotalBytes = memoryTotalBytes
        self.appResidentBytes = appResidentBytes; self.pressure = pressure; self.capturedAt = capturedAt
    }
}

public struct CompactionOperation: Codable, Equatable, Sendable {
    public var id: String
    public var chatID: String
    public var state: String
    public var message: String
    public init(id: String, chatID: String, state: String, message: String) {
        self.id = id; self.chatID = chatID; self.state = state; self.message = message
    }
}

public struct AppSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var demo = false
    public var providers: [ProviderState] = ProviderID.allCases.map { ProviderState(id: $0) }
    public var sessions: [ChatSession] = []
    public var selectedChatID: String?
    public var selectionRevision = 0
    public var metrics: SystemMetrics?
    public var operation: CompactionOperation?
    public var generatedAt = Date()
    public init() {}
    public var selectedChat: ChatSession? { sessions.first { $0.id == selectedChatID } }
}

public struct BridgeRequest: Codable, Sendable {
    public var version = 1
    public var command: String
    public var chatID: String?
    public var selectionRevision: Int?
    public var requestID: String?
    public var provider: ProviderID?
    public init(command: String, chatID: String? = nil, selectionRevision: Int? = nil,
                requestID: String? = nil, provider: ProviderID? = nil) {
        self.command = command; self.chatID = chatID; self.selectionRevision = selectionRevision
        self.requestID = requestID; self.provider = provider
    }
}

public struct BridgeResponse: Codable, Sendable {
    public var version = 1
    public var ok: Bool
    public var message: String?
    public var snapshot: AppSnapshot?
    public init(ok: Bool, message: String? = nil, snapshot: AppSnapshot? = nil) {
        self.ok = ok; self.message = message; self.snapshot = snapshot
    }
}

public enum CompactionGate {
    public static func rejection(request: BridgeRequest, snapshot: AppSnapshot, now: Date = Date()) -> String? {
        guard request.version == 1 else { return "Update the add-on to match this app." }
        guard let chat = snapshot.selectedChat, chat.id == request.chatID,
              snapshot.selectionRevision == request.selectionRevision else { return "Chat selection changed. Refresh and try again." }
        guard let requestID = request.requestID, !requestID.isEmpty, requestID.count <= 128 else { return "Missing operation identifier." }
        guard !snapshot.demo else { return "Demo mode cannot change a real chat." }
        guard chat.nativeCompactionAvailable else { return "Connect to the chat's existing app-server to enable compaction." }
        guard chat.runState == .idle else { return "The selected chat must be idle." }
        guard now.timeIntervalSince(chat.observedAt) < 60 else { return "Refresh the chat state before compacting." }
        if let op = snapshot.operation, op.state == "running" { return "Compaction is already in progress." }
        return nil
    }
}
