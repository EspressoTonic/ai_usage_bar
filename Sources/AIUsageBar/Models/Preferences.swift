import Foundation
import UsageCore

struct ProviderPreference: Codable {
    var enabled = false
    var credentialPath: String
    var project = ""
}
struct Preferences: Codable {
    var schemaVersion = 1
    var providers: [String: ProviderPreference] = [:]
    var monitorSystem = true
    var readLocalSessions = false
    var refreshSeconds: Double = 120
    var contextThreshold: Double = 80
    var rpcEndpoint = "ws://127.0.0.1:4500"
    var codexProfiles: [CodexProfile]?
    var menuQuota: MenuQuotaSelection?
    var showPace: Bool?
    var keepHistory: Bool?
    var notifications: Bool?
    var notifyResets: Bool?
    var lowQuotaThreshold: Double?
    init() {
        for provider in ProviderID.allCases {
            providers[provider.rawValue] = ProviderPreference(credentialPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(provider.credentialRelativePath).path)
        }
    }
}
