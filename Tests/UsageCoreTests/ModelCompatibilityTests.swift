import Foundation
import Testing
@testable import UsageCore

struct ModelCompatibilityTests {
    private func httpPool(_ feature: String, used: Double, name: String? = nil) -> [String: Any] {
        var pool: [String: Any] = ["metered_feature": feature,
            "rate_limit": ["primary_window": ["used_percent": used, "limit_window_seconds": 18000]]]
        if let name { pool["limit_name"] = name }
        return pool
    }
    @Test func modelPoolsKeepTheirIdentityAcrossInsertionAndReordering() {
        let sol = httpPool("gpt-6.2-sol", used: 15, name: "GPT-6.2 Sol")
        let astra = httpPool("gpt-6.2-astra", used: 35)
        let first = QuotaParser.codex(["additional_rate_limits": [sol, astra]])
        let reordered = QuotaParser.codex(["additional_rate_limits": [httpPool("future-model", used: 80), astra, sol]])
        #expect(first.count == 2 && reordered.count == 3)
        for window in first {
            #expect(reordered.first { $0.id == window.id } == window)
            #expect(!window.id.hasPrefix("extra-0-"))
        }
        #expect(first.contains { $0.label == "gpt-6.2-astra · 5 hours" })
        #expect(first.contains { $0.label == "GPT-6.2 Sol · 5 hours" })
    }
    @Test func malformedModelRowsNeverEraseSiblingsOrInventWindowDetails() {
        let valid = httpPool("gpt-6.2-sol", used: 42)
        let unknown: [String: Any] = ["metered_feature": "future-model",
            "rate_limit": ["secondary_window": ["used_percent": 7, "reset_at": true, "limit_window_seconds": -60]]]
        let values: [Any] = [false, NSNull(), "unknown-row", ["rate_limit": [:]], valid, unknown,
                             httpPool(String(repeating: "x", count: 257), used: 5)]
        let windows = QuotaParser.codex(["additional_rate_limits": values])
        #expect(windows.count == 2)
        let extra = windows.first { $0.label == "future-model · Secondary" }
        #expect(extra != nil && extra?.durationMinutes == nil && extra?.resetsAt == nil)
        let ambiguous = QuotaParser.codex(["additional_rate_limits": [valid, httpPool("gpt-6.2-sol", used: 90)]])
        #expect(ambiguous.isEmpty)
    }
    @Test func nativeNewModelAliasesDoNotDisplaceTheMainQuota() throws {
        let windows: [String: Any] = ["primary": ["usedPercent": 10, "windowDurationMins": 300],
                                     "secondary": ["usedPercent": 25, "windowDurationMins": 10080]]
        var extra: [String: Any] = windows
        extra["normalModelSlug"] = "gpt-6.2-astra"
        let limits: [String: Any] = ["accountId": "invented", "rateLimits": ["limitId": "codex"],
            "rateLimitsByLimitId": ["a-new-model-alias": extra, "broken-future-bucket": NSNull(), "codex": windows]]
        let result = try CodexQuotaExchange.parse(account: ["planType": "pro"], limits: limits, binding: "fixture")
        #expect(Array(result.windows.prefix(2)).map(\.id) == ["codex-primary", "codex-secondary"])
        #expect(result.windows.contains { $0.label == "gpt-6.2-astra · 5 hours" })
        var state = ProviderState(id: .codex, enabled: true); state.snapshot = result
        let menu = MenuQuotaPresentation.resolve(.automatic, sources: [MenuQuotaSource(id: "codex", title: "Codex", state: state)])
        #expect(menu.visibleText == "C 90% / 75%")
    }
    @Test func nativeBackendPrimaryBucketNameIsRespected() throws {
        let result = try CodexQuotaExchange.parse(account: [:], limits: [
            "rateLimits": ["limitId": "work-general"], "rateLimitsByLimitId": [
                "a-model": ["primary": ["usedPercent": 99]], "work-general": ["primary": ["usedPercent": 5]]]], binding: "fixture")
        #expect(result.windows.first?.id == "work-general-primary")
        #expect(result.windows.first?.usedPercent == 5)
    }
    @Test func currentModelContextsUseReportedCapacityRatherThanACatalog() throws {
        for (model, capacity) in [("gpt-6.2-sol", 500000), ("gpt-6.2-astra", 272000), ("gpt-6.2-astra", 1000000), ("future-model", 750000)] {
            let head = Data("{\"type\":\"session_meta\",\"payload\":{\"id\":\"invented-chat\",\"source\":\"cli\"}}\n".utf8)
            let records: [[String: Any]] = [
                ["type": "turn_context", "payload": ["model": model]],
                ["type": "event_msg", "payload": ["type": "token_count", "info": [
                    "total_token_usage": ["total_tokens": 9000000], "last_token_usage": ["total_tokens": 12000],
                    "model_context_window": capacity]]]]
            var tail = Data()
            for record in records { tail.append(try JSONSerialization.data(withJSONObject: record)); tail.append(10) }
            let chat = try #require(SessionMetadata.parse(head: head, tail: tail, modifiedAt: Date(), fallbackTitle: "Invented"))
            #expect(chat.model == model && chat.capacity == capacity && chat.tokens == 12000)
            #expect(chat.contextPercent == Double(12000) / Double(capacity) * 100)
        }
    }
    private func antigravityReport(_ groups: [Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": "SUCCESS", "command": ["name": "usage", "data": ["groups": groups]]])
    }
    @Test func antigravityPinsSurviveNewGroupsAndBucketReordering() throws {
        let weekly: [String: Any] = ["bucket_id": "gemini-week", "display_name": "Weekly", "remaining_fraction": 0.6]
        let session: [String: Any] = ["bucket_id": "gemini-session", "display_name": "5 hours", "remaining_fraction": 0.8]
        let original = try AntigravityClient.windows(antigravityReport([
            ["display_name": "Gemini Models", "buckets": [weekly, session]]]))
        let updated = try AntigravityClient.windows(antigravityReport([
            ["display_name": "Future Models", "buckets": [["bucket_id": "future", "display_name": "Weekly", "remaining_fraction": 0.1]]],
            ["display_name": "Gemini Models", "buckets": [session, weekly]]]))
        #expect(original.count == 2 && updated.count == 3)
        for window in original { #expect(updated.first { $0.id == window.id } == window) }
        var state = ProviderState(id: .antigravity, enabled: true)
        state.snapshot = ProviderSnapshot(id: .antigravity, accountKey: "fixture", source: "fixture", windows: updated)
        let pin = MenuQuotaSelection(source: "antigravity", window: original[0].id)
        #expect(pin.percentage(in: state) == 60)
    }
    @Test func antigravityMalformedAndAmbiguousRowsCannotRetargetPins() throws {
        let weekly: [String: Any] = ["display_name": "Weekly", "remaining_fraction": 0.6]
        let original = try AntigravityClient.windows(antigravityReport([
            ["display_name": "Gemini Models", "buckets": [weekly]]]))
        let updated = try AntigravityClient.windows(antigravityReport([
            NSNull(), false, ["display_name": "Gemini Models", "buckets": [NSNull(), weekly]],
            ["display_name": "Ambiguous", "buckets": [weekly, weekly]],
            ["buckets": [["remaining_fraction": 0.9]]]]))
        #expect(updated == original)
        let other = try AntigravityClient.windows(antigravityReport([
            ["display_name": "Another Model", "buckets": [weekly]]]))
        #expect(other[0].id != original[0].id)
    }
    @Test func futureProviderModelsRemainDataDrivenAndSpendingStaysSeparate() {
        let claude = QuotaParser.claude(["seven_day_fable": ["utilization": 15],
            "five_hour_future_model": ["utilization": 25], "extra_usage": ["used_credits": 500]])
        #expect(claude.count == 2 && claude.first { $0.id == "seven_day_fable" }?.durationMinutes == 10080)
        let gemini = QuotaParser.gemini(["buckets": [
            ["modelId": "gemini-3-pro-preview", "remainingFraction": 0.6],
            ["modelId": "gemini-future-preview", "remainingFraction": 0.8],
            ["modelId": "invalid", "remainingFraction": true]]])
        #expect(gemini.count == 2 && gemini.contains { $0.id == "gemini-future-preview" })
    }
}
