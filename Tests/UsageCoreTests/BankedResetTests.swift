import Foundation
import Testing
@testable import UsageCore

struct BankedResetTests {
    @Test func inventoryRetainsOnlyAuthoritativeAvailableCount() throws {
        let privateID = "synthetic-reset-do-not-redeem"
        let inventory: [String: Any] = ["available_count": 3, "credits": [["id": privateID, "status": "available"]]]
        let credit = try #require(CodexBankedResets.credits(from: inventory))
        #expect(credit.resetCredits == 3)
        let encoded = try JSONEncoder().encode(credit)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(privateID))
        #expect(CodexBankedResets.credits(from: ["available_count": 0, "credits": [["id": privateID]]])?.resetCredits == 0)
        #expect(CodexBankedResets.credits(from: ["credits": [["id": privateID]]]) == nil)
        for invalid: Any in [true, -1, 1.5, "2", NSNull()] {
            #expect(CodexBankedResets.credits(from: ["available_count": invalid]) == nil)
        }
    }
    @Test func codexQuotaAllowlistCannotBuildResetSpendingRequests() {
        #expect(Set(CodexQuotaHTTPRoute.allCases.map(\.rawValue)) == ["usage", "rate-limit-reset-credits"])
        #expect(Set(CodexQuotaMethod.allCases.map(\.rawValue)) == ["initialize", "account/read", "account/rateLimits/read"])
        for route in CodexQuotaHTTPRoute.allCases {
            let request = route.request(token: "invented", account: "invented-workspace")
            #expect(request.httpMethod == "GET" && request.httpBody == nil)
            #expect(request.url?.scheme == "https" && request.url?.host == "chatgpt.com")
            #expect(request.url?.path == "/backend-api/wham/" + route.rawValue)
            #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "invented-workspace")
        }
    }
    @Test func inventoryReadUsesOneGETAndNeverSendsInventoryIDs() async throws {
        var calls = 0
        let value = try await CodexBankedResets.read(token: "invented", account: "invented-workspace") { request in
            calls += 1
            #expect(request.httpMethod == "GET" && request.httpBody == nil)
            #expect(request.url?.path == "/backend-api/wham/rate-limit-reset-credits")
            return ["available_count": 2, "credits": [["id": "synthetic-reset-do-not-redeem"]]]
        }
        #expect(calls == 1 && value?.resetCredits == 2)
    }
    @Test func unavailableInventoryDoesNotFailQuotaOrAttemptAnotherAction() async throws {
        var calls = 0
        let value = try await CodexBankedResets.read(token: "invented", account: nil) { request in
            calls += 1
            #expect(request.httpMethod == "GET")
            throw ProviderFailure(.server, "Synthetic inventory unavailable")
        }
        #expect(value == nil && calls == 1)
    }
    @Test func inventoryReadHonorsCancellation() async {
        let task = Task {
            try await CodexBankedResets.read(token: "invented", account: nil) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return ["available_count": 2]
            }
        }
        do { _ = try await task.value; #expect(Bool(false)) }
        catch { #expect(error is CancellationError) }
    }
}
