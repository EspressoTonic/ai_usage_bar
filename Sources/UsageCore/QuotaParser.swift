import Foundation
import CryptoKit

public enum QuotaParser {
    private static func percent(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let n = value.doubleValue
        return n.isFinite && (0...100).contains(n) ? n : nil
    }
    private static func date(_ raw: Any?) -> Date? {
        if let seconds = QuotaDetails.number(raw), seconds > 0, seconds < 253_402_300_800 { return Date(timeIntervalSince1970: seconds) }
        guard let string = raw as? String, string.utf8.count <= 100 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
    public static func codex(_ json: [String: Any]) -> [QuotaWindow] {
        var result: [QuotaWindow] = []
        func append(_ limits: [String: Any], prefix: String, title: String?) {
            for (key, fallback) in [("primary_window", "Primary"), ("secondary_window", "Secondary")] {
                guard let window = limits[key] as? [String: Any], let used = percent(window["used_percent"]) else { continue }
                let duration = QuotaDetails.integer(window["limit_window_seconds"], range: 60...31_536_000).map { $0 / 60 }
                let actualLabel = duration.map(windowLabel) ?? fallback
                result.append(QuotaWindow(id: prefix + key, label: title.map { "\($0) · \(actualLabel)" } ?? actualLabel,
                                          usedPercent: used, resetsAt: date(window["reset_at"]), durationMinutes: duration))
            }
        }
        if let limits = json["rate_limit"] as? [String: Any] { append(limits, prefix: "codex-", title: nil) }
        // One malformed or future row must not erase its valid siblings. Identity is
        // the metered feature, not array order, so new models cannot retarget a pin.
        var extras: [String: [(title: String, limits: [String: Any])]] = [:]
        for row in ((json["additional_rate_limits"] as? [Any]) ?? []).prefix(32) {
            guard let extra = row as? [String: Any], let limits = extra["rate_limit"] as? [String: Any],
                  let rawIdentity = extra["metered_feature"] as? String
                    ?? extra["limit_name"] as? String ?? extra["name"] as? String,
                  rawIdentity.utf8.count <= 256,
                  let identity = QuotaDetails.text(rawIdentity, maximum: 256),
                  identity == rawIdentity.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            let digest = SHA256.hash(data: Data(identity.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
            let title = QuotaDetails.text(extra["limit_name"]) ?? QuotaDetails.text(extra["name"])
                ?? QuotaDetails.text(extra["metered_feature"]) ?? identity
            extras[digest, default: []].append((title, limits))
        }
        for key in extras.keys.sorted() {
            // Duplicate identities are ambiguous; do not let row order select a value.
            guard let rows = extras[key], rows.count == 1, let extra = rows.first else { continue }
            append(extra.limits, prefix: "codex-extra-" + key + "-", title: extra.title)
        }
        return result
    }
    public static func claude(_ json: [String: Any]) -> [QuotaWindow] {
        json.keys.sorted().compactMap { key in
            guard key.hasPrefix("five_hour") || key.hasPrefix("seven_day"),
                  let window = json[key] as? [String: Any], let used = percent(window["utilization"]) else { return nil }
            let label = key == "five_hour" ? "5 hours" : key == "seven_day" ? "Weekly" : key.replacingOccurrences(of: "_", with: " ").capitalized
            return QuotaWindow(id: key, label: label, usedPercent: used, resetsAt: date(window["resets_at"]),
                               durationMinutes: key.hasPrefix("five_hour") ? 300 : 10080)
        }
    }
    public static func gemini(_ json: [String: Any]) -> [QuotaWindow] {
        var byModel: [String: QuotaWindow] = [:]
        for bucket in (json["buckets"] as? [[String: Any]]) ?? [] {
            guard let model = bucket["modelId"] as? String,
                  let fraction = QuotaDetails.number(bucket["remainingFraction"]),
                  fraction.isFinite, (0...1).contains(fraction) else { continue }
            let window = QuotaWindow(id: model, label: model, usedPercent: (1 - fraction) * 100,
                                     resetsAt: date(bucket["resetTime"]))
            if (byModel[model]?.usedPercent ?? -1) < window.usedPercent { byModel[model] = window }
        }
        return byModel.values.sorted { $0.label < $1.label }
    }
    public static func windowLabel(minutes: Int) -> String {
        if minutes == 10080 { return "Weekly" }
        if minutes > 0 && minutes % 1440 == 0 { return "\(minutes / 1440) days" }
        if minutes > 0 && minutes % 60 == 0 { return "\(minutes / 60) hours" }
        return "\(minutes) minutes"
    }
}
import CoreFoundation
