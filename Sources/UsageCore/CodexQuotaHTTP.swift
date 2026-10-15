import Foundation

/// Complete HTTP allowlist for Codex quota reads. No reset-redemption route or POST exists.
enum CodexQuotaHTTPRoute: String, CaseIterable {
    case usage = "usage"
    case bankedResets = "rate-limit-reset-credits"
    func request(token: String, account: String?) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/" + rawValue)!)
        request.httpMethod = "GET"; request.timeoutInterval = 8
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let account, !account.isEmpty { request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
        if self == .bankedResets { request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta") }
        return request
    }
}

enum CodexBankedResets {
    /// Only the authoritative count is retained. Inventory IDs/details cannot enter the model.
    static func credits(from json: [String: Any]) -> QuotaCredits? {
        QuotaDetails.credits([:], id: "reset-credits", label: "Banked resets", resetCount: json["available_count"])
    }
    static func read(token: String, account: String?, send: (URLRequest) async throws -> [String: Any]) async throws -> QuotaCredits? {
        try Task.checkCancellation()
        do {
            let json = try await send(CodexQuotaHTTPRoute.bankedResets.request(token: token, account: account))
            try Task.checkCancellation()
            return credits(from: json)
        } catch {
            try Task.checkCancellation()
            // An unavailable optional inventory must not discard a valid quota reading.
            return nil
        }
    }
}
