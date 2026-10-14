import Foundation
import UsageCore

enum DemoContent {
    static func snapshot() -> AppSnapshot {
        var value = AppSnapshot(); value.demo = true
        let quotas: [(ProviderID, [(String, Double)])] = [(.codex, [("5 hours", 28), ("Weekly", 59)]),
            (.antigravity, [("Gemini Models · Weekly", 23), ("Gemini Models · 5 hours", 8), ("Claude + GPT · Weekly", 42), ("Claude + GPT · 5 hours", 16)]),
            (.gemini, [("Gemini Pro", 34), ("Gemini Flash", 12)]), (.claude, [("5 hours", 47), ("Weekly", 31)])]
        value.providers = quotas.map { provider, windows in
            var state = ProviderState(id: provider, enabled: true)
            state.snapshot = ProviderSnapshot(id: provider, accountKey: "demo", source: "Demonstration data", windows: windows.enumerated().map {
                QuotaWindow(id: "demo-\($0.offset)", label: $0.element.0, usedPercent: $0.element.1, resetsAt: Date().addingTimeInterval(Double($0.offset + 1) * 5400))
            })
            return state
        }
        value.sessions = [ChatSession(id: "demo-chat-1", title: "ai_usage_bar", client: "Codex desktop", model: "Current model",
                                     tokens: 164_000, capacity: 200_000, runState: .idle, source: .demo),
                          ChatSession(id: "demo-chat-2", title: "Backend tests", client: "Codex CLI", tokens: 71_000,
                                      capacity: 200_000, runState: .running, source: .demo)]
        value.selectedChatID = value.sessions[0].id
        value.metrics = SystemMetrics(cpuPercent: 12.4, memoryUsedBytes: 10_093_174_784, memoryTotalBytes: 25_769_803_776,
                                     appResidentBytes: 31_457_280, pressure: "Normal")
        return value
    }
}
