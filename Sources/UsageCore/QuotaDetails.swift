import Foundation

public struct AccountIdentity: Codable, Equatable, Sendable {
    public var email: String?
    public var plan: String?
    public var workspace: String?
    public init(email: String? = nil, plan: String? = nil, workspace: String? = nil) {
        self.email = email; self.plan = plan; self.workspace = workspace
    }
}
public struct QuotaCredits: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var balance: String?
    public var unlimited: Bool?
    public var hasCredits: Bool?
    public var resetCredits: Int?
    public init(id: String, label: String, balance: String? = nil, unlimited: Bool? = nil,
                hasCredits: Bool? = nil, resetCredits: Int? = nil) {
        self.id = id; self.label = label; self.balance = balance; self.unlimited = unlimited
        self.hasCredits = hasCredits; self.resetCredits = resetCredits
    }
}

public enum QuotaDetails {
    public static func text(_ value: Any?, maximum: Int = 100) -> String? {
        guard let raw = value as? String else { return nil }
        let clean = String(raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) &&
            !CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}").contains($0) }.prefix(maximum))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }
    static func integer(_ value: Any?, range: ClosedRange<Int>) -> Int? {
        guard let n = number(value), n.rounded() == n, n >= Double(range.lowerBound), n <= Double(range.upperBound) else { return nil }
        return Int(n)
    }
    static func boolean(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }
    public static func credits(_ raw: [String: Any], id: String, label: String, resetCount: Any? = nil) -> QuotaCredits? {
        var balance: String?
        if let rawBalance = raw["balance"] as? String, rawBalance.count <= 40,
           rawBalance.range(of: #"\A[0-9]+(\.[0-9]+)?\z"#, options: .regularExpression) != nil { balance = rawBalance }
        let value = QuotaCredits(id: id, label: label, balance: balance, unlimited: boolean(raw["unlimited"]),
            hasCredits: boolean(raw["hasCredits"] ?? raw["has_credits"]), resetCredits: integer(resetCount, range: 0...1_000_000))
        return value.balance != nil || value.unlimited != nil || value.hasCredits != nil || value.resetCredits != nil ? value : nil
    }
}

public struct QuotaPace: Equatable {
    public let expectedUsedPercent: Double
    public let projectedUsedPercent: Double
    public let exhaustionAt: Date?
    public var aheadOfTime: Bool { projectedUsedPercent > 100 }
    public static func estimate(window: QuotaWindow, capturedAt: Date, now: Date = Date()) -> QuotaPace? {
        let age = now.timeIntervalSince(capturedAt)
        guard age >= 0, age <= 600, window.usedPercent.isFinite, (0...100).contains(window.usedPercent),
              let minutes = window.durationMinutes, (1...525_600).contains(minutes), let reset = window.resetsAt else { return nil }
        let duration = Double(minutes) * 60, left = reset.timeIntervalSince(capturedAt)
        let elapsed = duration - left
        guard left > 0, left <= duration, elapsed / duration >= 0.03, reset > now else { return nil }
        let projected = window.usedPercent * duration / elapsed
        let exhaustion = window.usedPercent > 0 ? capturedAt.addingTimeInterval(elapsed * (100 - window.usedPercent) / window.usedPercent) : nil
        return QuotaPace(expectedUsedPercent: elapsed / duration * 100, projectedUsedPercent: projected,
                         exhaustionAt: exhaustion.flatMap { $0 < reset ? $0 : nil })
    }
}

public struct QuotaPoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var source: String
    public var account: String
    public var window: String
    public var capturedAt: Date
    public var usedPercent: Double
    public var resetsAt: Date?
}
public struct QuotaHistory: Codable, Equatable, Sendable {
    public private(set) var points: [QuotaPoint] = []
    public init() {}
    public mutating func record(source: String, reading: ProviderSnapshot, now: Date = Date()) {
        prune(now: now)
        guard reading.id != .antigravity, reading.identityVerified == true, !reading.accountKey.isEmpty,
              now.timeIntervalSince(reading.capturedAt) >= 0, now.timeIntervalSince(reading.capturedAt) <= 600 else { return }
        for window in reading.windows.prefix(64) where window.usedPercent.isFinite && (0...100).contains(window.usedPercent) &&
            window.resetsAt.map({ $0 > reading.capturedAt }) == true {
            let previous = points.last { $0.source == source && $0.account == reading.accountKey && $0.window == window.id }
            if let previous, previous.resetsAt == window.resetsAt, previous.usedPercent == window.usedPercent { continue }
            if let previous, reading.capturedAt <= previous.capturedAt { continue }
            points.append(QuotaPoint(id: UUID().uuidString, source: source, account: reading.accountKey, window: window.id,
                                     capturedAt: reading.capturedAt, usedPercent: window.usedPercent, resetsAt: window.resetsAt))
        }
        prune(now: now)
    }
    public mutating func prune(now: Date = Date(), sources: Set<String>? = nil) {
        points.removeAll { now.timeIntervalSince($0.capturedAt) > 7 * 86400 || $0.capturedAt > now }
        if let sources { points.removeAll { !sources.contains($0.source) } }
        points = Array(points.suffix(1000))
    }
    public func series(source: String, account: String, window: QuotaWindow) -> [QuotaPoint] {
        guard window.resetsAt != nil else { return [] }
        return points.filter { $0.source == source && $0.account == account && $0.window == window.id && $0.resetsAt == window.resetsAt }
            .sorted { $0.capturedAt < $1.capturedAt }
    }
}

public enum QuotaAlert: String, Equatable { case low, reset }
/// Only successful fresh polls enter this state machine. No startup/stale-cache notifications.
public struct QuotaAlertTracker {
    private struct Observation { var used: Double; var reset: Date; var captured: Date; var lowSent: Bool }
    private var values: [String: Observation] = [:]
    public init() {}
    public mutating func clear() { values.removeAll() }
    public mutating func observe(source: String, reading: ProviderSnapshot, threshold: Double, now: Date = Date()) -> Set<QuotaAlert> {
        guard reading.id != .antigravity, reading.identityVerified == true, (1...50).contains(threshold),
              now.timeIntervalSince(reading.capturedAt) >= 0, now.timeIntervalSince(reading.capturedAt) <= 600 else { return [] }
        var events = Set<QuotaAlert>()
        for window in reading.windows.prefix(64) {
            guard window.usedPercent.isFinite, (0...100).contains(window.usedPercent), let reset = window.resetsAt, reset > now else { continue }
            let key = source + "|" + reading.accountKey + "|" + window.id
            let previous = values[key]
            guard previous == nil || reading.capturedAt > previous!.captured else { continue }
            let sameCycle = previous?.reset == reset
            let low = window.remainingPercent <= threshold
            if let previous {
                if sameCycle && previous.used < 100 - threshold && low && !previous.lowSent { events.insert(.low) }
                if reset > previous.reset && previous.reset <= reading.capturedAt && window.usedPercent < previous.used { events.insert(.reset) }
            }
            values[key] = Observation(used: window.usedPercent, reset: reset, captured: reading.capturedAt,
                                     lowSent: sameCycle ? (previous?.lowSent == true || low) : low)
        }
        if values.count > 1024 { values.removeAll() }
        return events
    }
}

public struct MenuQuotaSelection: Codable, Equatable, Hashable, Sendable {
    public var source: String
    public var window: String
    public init(source: String, window: String) { self.source = source; self.window = window }
    public func percentage(in state: ProviderState, now: Date = Date()) -> Int? {
        guard state.enabled, state.error == nil, let reading = state.snapshot,
              now.timeIntervalSince(reading.capturedAt) >= 0, now.timeIntervalSince(reading.capturedAt) <= 600,
              let value = reading.windows.first(where: { $0.id == window }), value.usedPercent.isFinite,
              (0...100).contains(value.usedPercent), value.resetsAt.map({ $0 > now }) ?? true else { return nil }
        return Int(value.remainingPercent.rounded())
    }
}
