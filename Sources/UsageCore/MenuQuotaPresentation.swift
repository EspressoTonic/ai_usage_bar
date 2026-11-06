import Foundation

public enum MenuQuotaDisplay: Codable, Hashable, Sendable {
    case automatic, iconOnly
    case source(String)
    case window(MenuQuotaSelection)
}

public struct MenuQuotaSource: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let state: ProviderState

    public init(id: String, title: String, state: ProviderState) {
        self.id = id; self.title = title; self.state = state
    }
}

/// A bounded view of cached readings. Never averages windows or combines accounts.
public struct MenuQuotaPresentation: Equatable, Sendable {
    public struct Limit: Equatable, Sendable {
        public let label: String
        public let remaining: Int?
    }

    public let title: String
    public let prefix: String?
    public let limits: [Limit]

    public var visibleText: String? {
        prefix.map { prefix in
            prefix + " " + limits.map { $0.remaining.map { "\($0)%" } ?? "—" }.joined(separator: " / ")
        }
    }

    public var accessibilityText: String {
        let descriptions = limits.map { limit in
            limit.label + ": " + (limit.remaining.map { "\($0) percent remaining" } ?? "unavailable")
        }
        return ([title] + descriptions).joined(separator: ". ")
    }

    public static func resolve(_ display: MenuQuotaDisplay, sources: [MenuQuotaSource],
                               now: Date = Date(), maximumAge: TimeInterval = 600) -> Self {
        let enabled = sources.filter { $0.state.enabled }
        func limits(for source: MenuQuotaSource, windowID: String? = nil) -> [Limit] {
            let windows = source.state.snapshot?.windows ?? []
            return windows.lazy.filter { windowID == nil || $0.id == windowID }.prefix(windowID == nil ? 2 : 1).map { window in
                let selection = MenuQuotaSelection(source: source.id, window: window.id)
                return Limit(label: window.label, remaining: selection.percentage(in: source.state, now: now, maximumAge: maximumAge))
            }
        }
        let source: MenuQuotaSource?
        let windowID: String?
        switch display {
        case .iconOnly:
            return Self(title: "AI Usage Bar", prefix: nil, limits: [])
        case .automatic:
            source = enabled.first { limits(for: $0).contains { $0.remaining != nil } }
                ?? enabled.first { $0.state.snapshot?.windows.isEmpty == false }
                ?? enabled.first
            windowID = nil
            if source == nil { return Self(title: "AI Usage Bar · No quota sources enabled", prefix: nil, limits: []) }
        case let .source(id):
            source = enabled.first { $0.id == id }; windowID = nil
        case let .window(selection):
            source = enabled.first { $0.id == selection.source }; windowID = selection.window
        }
        guard let source else {
            return Self(title: "Selected source unavailable", prefix: "Q", limits: [Limit(label: "Quota", remaining: nil)])
        }
        let shown = limits(for: source, windowID: windowID)
        let prefix: String
        switch source.state.id {
        case .codex: prefix = "C"
        case .claude: prefix = "Cl"
        case .gemini: prefix = "G"
        case .antigravity: prefix = "A"
        }
        return Self(title: source.title, prefix: prefix, limits: shown.isEmpty
                    ? [Limit(label: windowID == nil ? "Quota" : "Selected limit", remaining: nil)] : shown)
    }
}
