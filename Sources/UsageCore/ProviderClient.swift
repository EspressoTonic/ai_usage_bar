import Foundation
import CryptoKit

public struct ProviderFailure: Error, LocalizedError {
    public enum Kind { case configuration, authentication, transport, server, malformed, unsupported }
    public var kind: Kind
    public var message: String
    public var accountKey: String?
    public var retryAfter: TimeInterval?
    public var errorDescription: String? { message }
    public init(_ kind: Kind, _ message: String, accountKey: String? = nil, retryAfter: TimeInterval? = nil) {
        self.kind = kind; self.message = message; self.accountKey = accountKey; self.retryAfter = retryAfter
    }
}

public struct ProviderClient {
    public init() {}
    public func fetch(_ provider: ProviderID, credentialURL: URL, project: String = "") async throws -> ProviderSnapshot {
        if provider == .antigravity { return try await AntigravityClient().fetch(executableURL: credentialURL) }
        let raw: [String: Any]
        do {
            raw = try JSONSerialization.jsonObject(with: CredentialFile.read(credentialURL)) as? [String: Any] ?? [:]
        } catch let failure as ProviderFailure { throw failure }
        catch { throw ProviderFailure(.configuration, "CLI sign-in file could not be decoded. Renew it using the provider's CLI.") }
        let token: String?
        let account: String?
        var expiry: Double?
        switch provider {
        case .codex:
            let tokens = raw["tokens"] as? [String: Any]
            token = tokens?["access_token"] as? String
            account = tokens?["account_id"] as? String ?? raw["account_id"] as? String
        case .claude:
            let oauth = raw["claudeAiOauth"] as? [String: Any]
            token = oauth?["accessToken"] as? String
            expiry = oauth?["expiresAt"] as? Double
            account = oauth?["accountUuid"] as? String
        case .antigravity:
            throw ProviderFailure(.configuration, "Antigravity uses the agy executable rather than an OAuth file.")
        case .gemini:
            token = raw["access_token"] as? String
            expiry = raw["expiry_date"] as? Double
            account = raw["id_token"] as? String
        }
        guard let token, !token.isEmpty else {
            throw ProviderFailure(.configuration, provider == .claude
                ? "No OAuth token in this file. Claude Keychain sign-in is not supported by this first adapter."
                : "This adapter requires the CLI's Google/ChatGPT sign-in, not an API key.")
        }
        let fingerprint = SHA256.hash(data: Data((account ?? token).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        if let expiry, expiry / 1000 <= Date().timeIntervalSince1970 + 30 {
            throw ProviderFailure(.authentication, "CLI sign-in expired. Renew it in the CLI, then refresh here.", accountKey: fingerprint)
        }
        do {
            let json: [String: Any]
            let windows: [QuotaWindow]
            switch provider {
            case .codex:
                json = try await request(CodexQuotaHTTPRoute.usage.request(token: token, account: account))
                windows = QuotaParser.codex(json)
            case .claude:
                json = try await request("https://api.anthropic.com/api/oauth/usage", token: token,
                                         headers: ["anthropic-beta": "oauth-2025-04-20"])
                windows = QuotaParser.claude(json)
            case .antigravity:
                throw ProviderFailure(.configuration, "Antigravity uses the agy executable rather than an OAuth file.")
            case .gemini:
                let assist = try await request("https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist", token: token,
                                               body: ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]])
                let ineligible = assist["ineligibleTiers"] as? [[String: Any]] ?? []
                let tierID = (assist["currentTier"] as? [String: Any])?["id"] as? String
                let licensed = tierID == "standard-tier" || tierID == "enterprise-tier" || (assist["paidTier"] as? [String: Any])?["name"] as? String != nil
                if !licensed && ineligible.contains(where: { $0["reasonCode"] as? String == "UNSUPPORTED_CLIENT" }) {
                    throw ProviderFailure(.unsupported, "Google reports this Gemini CLI account/client as unsupported. For Antigravity quota, enable the separate Antigravity provider in Settings.")
                }
                let projectID = project.isEmpty ? assist["cloudaicompanionProject"] as? String : project
                json = try await request("https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota", token: token,
                                         body: projectID.map { ["project": $0] } ?? [:])
                windows = QuotaParser.gemini(json)
            }
            guard !windows.isEmpty else { throw ProviderFailure(.malformed, "No supported quota measurements in the response. Nothing has been assumed to be zero.") }
            var reading = ProviderSnapshot(id: provider, accountKey: fingerprint, source: "CLI OAuth · experimental endpoint", windows: windows)
            reading.identityVerified = account != nil
            if provider == .codex {
                reading.identity = AccountIdentity(plan: QuotaDetails.text(json["plan_type"]))
                if let value = QuotaDetails.credits(json["credits"] as? [String: Any] ?? [:], id: "codex", label: "Codex") { reading.credits = [value] }
                if let banked = try await CodexBankedResets.read(token: token, account: account, send: { try await request($0) }) {
                    reading.credits = (reading.credits ?? []) + [banked]
                }
            }
            return reading
        } catch var error as ProviderFailure {
            error.accountKey = fingerprint; throw error
        } catch is CancellationError { throw CancellationError() }
        catch {
            throw ProviderFailure(.transport, "Network request failed. The previous reading may be stale.", accountKey: fingerprint)
        }
    }
    private func request(_ address: String, token: String, headers: [String: String] = [:], body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: address)!)
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if let body {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await self.request(request)
    }
    private func request(_ request: URLRequest) async throws -> [String: Any] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 12
        let (data, http) = try await BoundedHTTP.data(for: request, configuration: configuration)
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw ProviderFailure(.authentication, "Provider rejected this sign-in or account tier. Renew the CLI sign-in and verify access.")
        case 429:
            let delay = RateLimitBackoff.delay(http.value(forHTTPHeaderField: "Retry-After"))
            throw ProviderFailure(.server, "Provider rate limited this request. Waiting before retrying.", retryAfter: delay)
        default: throw ProviderFailure(.server, "Provider returned HTTP \(http.statusCode).")
        }
        guard data.count <= 1_048_576, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ProviderFailure(.malformed, "Provider response could not be decoded.")
        }
        return json
    }
}

/// Credentials only reach the exact fixed endpoint; a redirect is an error, never a new token recipient.
final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
