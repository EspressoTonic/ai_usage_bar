import Foundation

public enum BridgePrivacy {
    public static func rejection(command: String, allowChatAccess: Bool) -> String? {
        if (command == "select" || command == "compact") && !allowChatAccess {
            return "Enable external chat access in the app's Settings for this launch."
        }
        return nil
    }
    public static func snapshot(_ value: AppSnapshot, allowChatAccess: Bool) -> AppSnapshot {
        var copy = value
        // Fingerprints are pseudonymous account metadata, not public identifiers.
        for index in copy.providers.indices {
            copy.providers[index].snapshot?.accountKey = "redacted"
            copy.providers[index].snapshot?.identity = nil
        }
        copy.codexProfiles = nil // Labels, source bindings and account details never leave through the bridge.
        if !allowChatAccess {
            copy.sessions = []; copy.selectedChatID = nil; copy.selectionRevision = 0; copy.operation = nil
        }
        return copy
    }
}

public struct CapturedAction: Codable {
    public var request: BridgeRequest
    public var createdAt: Date
    public init(request: BridgeRequest, createdAt: Date = Date()) { self.request = request; self.createdAt = createdAt }
    public func validate(at now: Date = Date()) throws -> BridgeRequest {
        let age = now.timeIntervalSince(createdAt)
        guard age >= -5, age <= 30, request.command == "compact", request.version == 1 else {
            throw BridgeError("Captured target expired. Refresh the display and try again.")
        }
        return request
    }
}
