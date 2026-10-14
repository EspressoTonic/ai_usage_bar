import Foundation
import Darwin

public struct AntigravityClient {
    public init() {}
    public func fetch(executableURL: URL) async throws -> ProviderSnapshot {
        let executable = try Self.executable(executableURL)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("aiub-agy-" + UUID().uuidString)
        do { try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700]) }
        catch { throw ProviderFailure(.configuration, "Antigravity CLI private working directory could not be prepared.") }
        defer { try? FileManager.default.removeItem(at: scratch) }
        do {
            let environment = try Self.environment(directory: scratch)
            let version = try await CommandProbe.run(executable: executable, arguments: ["--version"],
                                                    environment: environment, directory: scratch, timeout: 3, maximum: 16_384)
            guard version.status == 0, Self.supportsUsageReport(version.stdout) else {
                throw ProviderFailure(.unsupported, "Antigravity requires agy 1.1.11 or newer with structured /usage reports. Update agy and select its executable.")
            }
            let output = try await CommandProbe.run(executable: executable, arguments: ["-p", "/usage", "--output-format", "json"],
                                                   environment: environment, directory: scratch, timeout: 90)
            guard output.status == 0 else {
                let text = String(decoding: output.stderr + output.stdout, as: UTF8.self).lowercased()
                if ["not signed in", "not logged in", "sign in", "unauthenticated", "authentication required"].contains(where: { text.contains($0) }) {
                    throw ProviderFailure(.authentication, "Antigravity sign-in is unavailable. Open agy in a terminal and sign in, then refresh here.")
                }
                throw ProviderFailure(.transport, "Antigravity CLI could not retrieve usage. Check agy /usage in a terminal; private command output was not displayed.")
            }
            return ProviderSnapshot(id: .antigravity, accountKey: UUID().uuidString,
                                    source: "agy /usage · active CLI login; account identity not supplied",
                                    windows: try Self.windows(output.stdout))
        } catch is CancellationError { throw CancellationError() }
        catch let failure as ProviderFailure { throw failure }
        catch { throw ProviderFailure(.configuration, "Antigravity CLI probe could not be prepared. No credential files were copied.") }
    }
    static func executable(_ url: URL) throws -> URL {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.utf8.contains(0) else {
            throw ProviderFailure(.configuration, "Choose the Antigravity agy executable, normally ~/.local/bin/agy.")
        }
        let actual = url.resolvingSymlinksInPath()
        var info = stat()
        guard lstat(actual.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid() || info.st_uid == 0, info.st_mode & 0o022 == 0,
              access(actual.path, X_OK) == 0 else {
            throw ProviderFailure(.configuration, "Antigravity agy was not found or is not a safe executable. Select its actual executable path; no Gemini CLI sign-in file is needed.")
        }
        return actual
    }
    static func environment(directory: URL) throws -> [String: String] {
        // agy owns its existing default login. No copied grants or injected API
        // credentials. An empty workdir avoids loading project instructions.
        let inherited = ProcessInfo.processInfo.environment
        let allowed: Set<String> = ["HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE",
            "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy",
            "SSL_CERT_FILE", "SSL_CERT_DIR", "GEMINI_CLI_HOME"]
        var result = inherited.filter { allowed.contains($0.key) }
        result["HOME"] = result["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        let guardBody = Data("#!/bin/sh\nexit 1\n".utf8)
        for name in ["open", "xdg-open"] {
            try PrivateFiles.write(guardBody, directory: directory, name: name)
            guard chmod(directory.appendingPathComponent(name).path, 0o700) == 0 else {
                throw ProviderFailure(.configuration, "Browser-launch protection could not be prepared; usage was not requested.")
            }
        }
        result["PATH"] = directory.path + ":" + (result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        result["BROWSER"] = directory.appendingPathComponent("open").path
        return result
    }
    static func supportsUsageReport(_ data: Data) -> Bool {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.range(of: #"^(?:agy\s+(?:version\s+)?)?\d+\.\d+\.\d+$"#, options: .regularExpression) else { return false }
        let numbers = text[match].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 3 else { return false }
        return numbers.lexicographicallyPrecedes([1, 1, 11]) == false
    }
    static func windows(_ data: Data) throws -> [QuotaWindow] {
        guard data.count <= 1_048_576,
              let report = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              report["status"] as? String == "SUCCESS",
              let command = report["command"] as? [String: Any], command["name"] as? String == "usage",
              let payload = command["data"] as? [String: Any], let groups = payload["groups"] as? [[String: Any]] else {
            throw ProviderFailure(.malformed, "Antigravity did not return a successful structured /usage report.")
        }
        func field(_ object: [String: Any], _ snake: String, _ camel: String) -> Any? { object[snake] ?? object[camel] }
        func label(_ value: Any?, fallback: String) -> String {
            guard let value = value as? String else { return fallback }
            let clean = value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? fallback : String(clean.prefix(80))
        }
        var result: [QuotaWindow] = []
        for (groupIndex, group) in groups.prefix(32).enumerated() {
            let groupName = label(field(group, "display_name", "displayName") ?? group["name"], fallback: "Quota")
            for (bucketIndex, bucket) in ((group["buckets"] as? [[String: Any]]) ?? []).prefix(32).enumerated() {
                if let disabled = bucket["disabled"] {
                    guard let value = disabled as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID(), !value.boolValue else { continue }
                }
                let remaining = bucket["remaining"] as? [String: Any] ?? [:]
                let oneof = ["remainingFraction", "remaining_fraction"].contains(remaining["case"] as? String ?? "") ? remaining["value"] : nil
                guard let number = (field(bucket, "remaining_fraction", "remainingFraction") ?? field(remaining, "remaining_fraction", "remainingFraction") ?? oneof) as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                      (0...1).contains(number.doubleValue) else { continue }
                let name = label(field(bucket, "display_name", "displayName") ?? bucket["name"], fallback: "Limit")
                let cadence = ((bucket["window"] as? String ?? "") + " " + name).lowercased()
                let duration = cadence.contains("week") ? 10080 : (cadence.contains("hour") && (cadence.contains("five") || cadence.contains("5"))) ? 300 : nil
                let rawReset = field(bucket, "reset_time", "resetTime") as? String
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let reset = rawReset.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
                result.append(QuotaWindow(id: "antigravity-\(groupIndex)-\(bucketIndex)", label: groupName + " · " + name,
                    usedPercent: (1 - number.doubleValue) * 100, resetsAt: reset, durationMinutes: duration))
            }
        }
        guard !result.isEmpty else { throw ProviderFailure(.unsupported, "Antigravity returned no measured, enabled quota limits. No allowance was assumed to be full or empty.") }
        return result
    }
}
