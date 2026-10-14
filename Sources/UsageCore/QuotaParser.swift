import Foundation

public enum QuotaParser {
    private static func percent(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        let n = value.doubleValue
        return n.isFinite && (0...100).contains(n) ? n : nil
    }
    private static func date(_ raw: Any?) -> Date? {
        if let seconds = raw as? Double, seconds.isFinite, seconds > 0 { return Date(timeIntervalSince1970: seconds) }
        guard let string = raw as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
    public static func codex(_ json: [String: Any]) -> [QuotaWindow] {
        var result: [QuotaWindow] = []
        func append(_ limits: [String: Any], prefix: String, title: String?) {
            for (key, label) in [("primary_window", "Session"), ("secondary_window", "Weekly")] {
                guard let window = limits[key] as? [String: Any], let used = percent(window["used_percent"]) else { continue }
                let duration = (window["limit_window_seconds"] as? Int).map { $0 / 60 }
                let actualLabel = duration == nil ? label : windowLabel(minutes: duration!)
                result.append(QuotaWindow(id: prefix + key, label: title.map { "\($0) · \(actualLabel)" } ?? actualLabel,
                                          usedPercent: used, resetsAt: date(window["reset_at"]), durationMinutes: duration))
            }
        }
        if let limits = json["rate_limit"] as? [String: Any] { append(limits, prefix: "codex-", title: nil) }
        for (index, extra) in ((json["additional_rate_limits"] as? [[String: Any]]) ?? []).enumerated() {
            if let limits = extra["rate_limit"] as? [String: Any] {
                append(limits, prefix: "extra-\(index)-", title: extra["limit_name"] as? String ?? extra["name"] as? String)
            }
        }
        return result
    }
    public static func claude(_ json: [String: Any]) -> [QuotaWindow] {
        json.keys.sorted().compactMap { key in
            guard key.hasPrefix("five_hour") || key.hasPrefix("seven_day"),
                  let window = json[key] as? [String: Any], let used = percent(window["utilization"]) else { return nil }
            let label = key == "five_hour" ? "5 hours" : key == "seven_day" ? "Weekly" : key.replacingOccurrences(of: "_", with: " ").capitalized
            return QuotaWindow(id: key, label: label, usedPercent: used, resetsAt: date(window["resets_at"]))
        }
    }
    public static func gemini(_ json: [String: Any]) -> [QuotaWindow] {
        var byModel: [String: QuotaWindow] = [:]
        for bucket in (json["buckets"] as? [[String: Any]]) ?? [] {
            guard let model = bucket["modelId"] as? String,
                  let fraction = bucket["remainingFraction"] as? Double,
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
