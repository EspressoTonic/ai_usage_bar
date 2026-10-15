import Foundation
import CryptoKit
import Darwin

public struct CodexProfile: Codable, Equatable, Identifiable, Sendable {
    public enum Location: String, Codable, CaseIterable, Sendable { case local, ssh }
    public var id: String
    public var label: String
    public var enabled: Bool
    public var location: Location
    public var host: String
    public var home: String
    public var executable: String
    public init(id: String = UUID().uuidString, label: String = "", enabled: Bool = false,
                location: Location = .local, host: String = "", home: String = "", executable: String = "") {
        self.id = id; self.label = label; self.enabled = enabled; self.location = location
        self.host = host; self.home = home; self.executable = executable
    }
    public var binding: String {
        SHA256.hash(data: Data([id, location.rawValue, host, home, executable].joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    public func validate() throws {
        guard UUID(uuidString: id) != nil, label == QuotaDetails.text(label, maximum: 60),
              Self.absolutePath(home), Self.absolutePath(executable), home != "/", executable != "/" else {
            throw ProviderFailure(.configuration, "Give the source a short label and absolute CODEX_HOME / executable paths.")
        }
        if location == .ssh {
            guard host.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$"#, options: .regularExpression) != nil else {
                throw ProviderFailure(.configuration, "Use an existing SSH config alias containing letters, numbers, dots, underscores or hyphens.")
            }
        }
    }
    private static func absolutePath(_ value: String) -> Bool {
        value.hasPrefix("/") && value.utf8.count <= 1024 && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    public func sshArguments() throws -> [String] {
        try validate()
        guard location == .ssh else { throw ProviderFailure(.configuration, "This source is local.") }
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
        let bin = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        // All user-controlled text is one POSIX shell argument, never an SSH option or shell expression.
        let command = "exec env CODEX_HOME=" + quote(home) + " PATH=" + quote(bin + ":/usr/local/bin:/usr/bin:/bin") + " " + quote(executable) + " app-server"
        return ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=yes", "-o", "ClearAllForwardings=yes",
                "-o", "PermitLocalCommand=no", "-o", "ForwardAgent=no", "-o", "ForwardX11=no", "-o", "ControlMaster=no", "-o", "ControlPath=none", "--", host, command]
    }
}

public struct CodexProfileState: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var binding: String
    public var label: String
    public var state: ProviderState
    public init(profile: CodexProfile) {
        id = profile.id; binding = profile.binding; label = profile.label
        state = ProviderState(id: .codex, enabled: profile.enabled)
    }
}

/// Native authentication stays with Codex, including keyring-backed profiles.
public struct CodexQuotaClient {
    public init() {}
    public func fetch(profile: CodexProfile) async throws -> ProviderSnapshot {
        try profile.validate()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("aiub-codex-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable: URL, arguments: [String]
        var environment = Self.environment(directory: directory)
        if profile.location == .local {
            var info = stat()
            guard lstat(profile.home, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else {
                throw ProviderFailure(.configuration, "CODEX_HOME must be a real directory owned by you with owner-only permissions.")
            }
            try Self.trustedParents(of: URL(fileURLWithPath: profile.home))
            executable = try Self.safeExecutable(profile.executable)
            arguments = ["app-server"]
            environment["CODEX_HOME"] = profile.home
            let launcher = URL(fileURLWithPath: profile.executable)
            try Self.trustedParents(of: launcher)
            environment["PATH"] = launcher.deletingLastPathComponent().path + ":" + executable.deletingLastPathComponent().path + ":/usr/local/bin:/usr/bin:/bin"
        } else {
            executable = URL(fileURLWithPath: "/usr/bin/ssh"); arguments = try profile.sshArguments()
        }
        let exchange = CodexQuotaExchange(binding: profile.binding)
        let output = try await CommandProbe.run(executable: executable, arguments: arguments, environment: environment,
            directory: directory, timeout: 30, dialogue: try exchange.dialogue())
        guard output.status == 0, let reading = exchange.reading else {
            throw ProviderFailure(.authentication, "Native Codex quota is unavailable. Check this source's CLI login, version and SSH access in a terminal.")
        }
        return reading
    }
    static func safeExecutable(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid() || info.st_uid == 0, info.st_mode & 0o022 == 0, access(url.path, X_OK) == 0 else {
            throw ProviderFailure(.configuration, "Select a trusted Codex executable owned by you or root and not writable by others.")
        }
        try trustedParents(of: url)
        return url
    }
    static func trustedParents(of url: URL) throws {
        var parent = url.deletingLastPathComponent()
        while true {
            var info = stat()
            guard stat(parent.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
                  info.st_uid == geteuid() || info.st_uid == 0,
                  info.st_mode & 0o022 == 0 || (info.st_uid == 0 && info.st_mode & S_ISVTX != 0) else {
                throw ProviderFailure(.configuration, "A source path has a parent directory that can be changed by another user.")
            }
            if parent.path == "/" { break }
            parent.deleteLastPathComponent()
        }
    }
    static func environment(directory: URL) -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        let allowed = ["HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "SSH_AUTH_SOCK",
                       "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy",
                       "SSL_CERT_FILE", "SSL_CERT_DIR", "NODE_EXTRA_CA_CERTS"]
        var value: [String: String] = [:]
        for key in allowed { if let raw = source[key] { value[key] = raw } }
        value["PATH"] = "/usr/bin:/bin"; value["TMPDIR"] = directory.path
        return value
    }
}

/// The quota exchange cannot construct a spending, redemption, login or thread request.
enum CodexQuotaMethod: String, CaseIterable {
    case initialize
    case accountRead = "account/read"
    case rateLimitsRead = "account/rateLimits/read"
}

final class CodexQuotaExchange {
    let binding: String
    private var expected = 1
    private var account: [String: Any]?
    private var limits: [String: Any]?
    private(set) var reading: ProviderSnapshot?
    init(binding: String) { self.binding = binding }
    private func request(_ id: Int, _ method: CodexQuotaMethod, _ params: [String: Any] = [:]) throws -> Data {
        var value = try JSONSerialization.data(withJSONObject: ["id": id, "method": method.rawValue, "params": params]); value.append(10); return value
    }
    func dialogue() throws -> ProbeDialogue {
        ProbeDialogue(initialInput: try request(1, .initialize, ["clientInfo": ["name": "ai_usage_bar", "version": "0.1.0"]])) { [self] line in
            try receive(line)
        }
    }
    func receive(_ line: Data) throws -> (input: Data, finished: Bool) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw ProviderFailure(.malformed, "Codex returned an invalid protocol message.")
        }
        // No server requests are serviced. Notifications carry no state for this read-only exchange.
        if object["id"] == nil { return (Data(), false) }
        guard QuotaDetails.integer(object["id"], range: 1...4) == expected, object["method"] == nil else {
            throw ProviderFailure(.malformed, "Codex returned an unexpected protocol response.")
        }
        guard object["error"] == nil, let result = object["result"] as? [String: Any] else {
            throw ProviderFailure(.unsupported, "Codex could not read this account's quota. Check native sign-in and app-server support.")
        }
        var outgoing = Data()
        switch expected {
        case 1:
            outgoing = Data("{\"method\":\"initialized\"}\n".utf8)
            outgoing.append(try request(2, .accountRead, ["refreshToken": false]))
        case 2:
            guard let value = result["account"] as? [String: Any], value["type"] as? String == "chatgpt" else {
                throw ProviderFailure(.authentication, "Sign in to this source with a ChatGPT account using its Codex CLI.")
            }
            account = value; outgoing = try request(3, .rateLimitsRead)
        case 3:
            limits = result; outgoing = try request(4, .accountRead, ["refreshToken": false])
        case 4:
            guard let second = result["account"] as? [String: Any], let account,
                  (account as NSDictionary).isEqual(to: second), let limits else {
                throw ProviderFailure(.authentication, "Codex account changed during the read. Refresh to verify the current source.")
            }
            reading = try Self.parse(account: account, limits: limits, binding: binding)
            return (Data(), true)
        default: throw ProviderFailure(.malformed, "Unexpected Codex protocol state.")
        }
        expected += 1
        return (outgoing, false)
    }
    static func parse(account: [String: Any], limits: [String: Any], binding: String) throws -> ProviderSnapshot {
        var windows: [QuotaWindow] = [], credits: [QuotaCredits] = []
        let buckets = limits["rateLimitsByLimitId"] as? [String: [String: Any]]
        let values: [(String, [String: Any])]
        if let buckets, !buckets.isEmpty { values = buckets.keys.sorted().prefix(32).map { ($0, buckets[$0]!) } }
        else if let legacy = limits["rateLimits"] as? [String: Any] { values = [("codex", legacy)] }
        else { values = [] }
        for (key, value) in values {
            guard key.utf8.count <= 120, QuotaDetails.text(key, maximum: 120) == key else { continue }
            let label = QuotaDetails.text(value["limitName"]) ?? QuotaDetails.text(value["limitId"]) ?? QuotaDetails.text(key) ?? "Codex"
            for name in ["primary", "secondary"] {
                guard let window = value[name] as? [String: Any], let used = QuotaDetails.number(window["usedPercent"]), (0...100).contains(used) else { continue }
                let minutes = QuotaDetails.integer(window["windowDurationMins"], range: 1...525_600)
                let reset = QuotaDetails.number(window["resetsAt"]).flatMap { $0 > 0 && $0 < 253_402_300_800 ? Date(timeIntervalSince1970: $0) : nil }
                windows.append(QuotaWindow(id: String(key.prefix(120)) + "-" + name,
                    label: label + " · " + (minutes.map { QuotaParser.windowLabel(minutes: $0) } ?? (name == "primary" ? "Primary" : "Secondary")),
                    usedPercent: used, resetsAt: reset, durationMinutes: minutes))
            }
            if let credit = QuotaDetails.credits(value["credits"] as? [String: Any] ?? [:], id: String(key.prefix(120)), label: label) { credits.append(credit) }
        }
        if let reset = limits["rateLimitResetCredits"] as? [String: Any],
           let credit = QuotaDetails.credits([:], id: "reset-credits", label: "Banked resets", resetCount: reset["availableCount"]) { credits.append(credit) }
        guard !windows.isEmpty else { throw ProviderFailure(.malformed, "Codex reported no supported quota windows. Missing values remain unknown.") }
        let accountID = QuotaDetails.text(limits["accountId"], maximum: 200)
        let identity = AccountIdentity(email: QuotaDetails.text(account["email"]), plan: QuotaDetails.text(account["planType"]), workspace: QuotaDetails.text(account["workspaceName"]))
        let key = SHA256.hash(data: Data((binding + "|" + (accountID ?? UUID().uuidString)).utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        var reading = ProviderSnapshot(id: .codex, accountKey: key, source: "Native Codex · selected CODEX_HOME", windows: windows)
        reading.identity = identity; reading.identityVerified = accountID != nil; reading.credits = credits.isEmpty ? nil : credits
        return reading
    }
}
