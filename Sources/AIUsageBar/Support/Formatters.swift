import Foundation

enum DisplayFormat {
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }
    static func age(_ date: Date?) -> String {
        guard let date else { return "No reading yet" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "Checked just now" }
        if seconds < 3600 { return "Checked \(seconds / 60)m ago" }
        return "Checked \(seconds / 3600)h ago"
    }
    static func interval(to date: Date) -> String {
        let minutes = max(1, Int(date.timeIntervalSinceNow / 60))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1440 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes / 1440)d \((minutes % 1440) / 60)h"
    }
    static func reset(_ date: Date?) -> String {
        guard let date else { return "Reset time unavailable" }
        let minutes = Int(date.timeIntervalSinceNow / 60)
        if minutes <= 0 { return "Reset due · refresh to verify" }
        return "Resets in " + interval(to: date)
    }
}
