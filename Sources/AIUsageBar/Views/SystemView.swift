import SwiftUI
import UsageCore

struct SystemView: View {
    let metrics: SystemMetrics?
    let enabled: Bool
    var body: some View {
        if let metrics {
            VStack(alignment: .leading, spacing: 14) {
                metric("CPU", icon: "cpu", value: metrics.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "Sampling…", fraction: (metrics.cpuPercent ?? 0) / 100)
                metric("Memory", icon: "memorychip", value: DisplayFormat.bytes(metrics.memoryUsedBytes),
                       fraction: metrics.memoryTotalBytes > 0 ? Double(metrics.memoryUsedBytes) / Double(metrics.memoryTotalBytes) : 0)
                HStack { Text("Installed RAM"); Spacer(); Text(DisplayFormat.bytes(metrics.memoryTotalBytes)).monospacedDigit() }.font(.caption)
                HStack { Text("Memory pressure"); Spacer(); Text(metrics.pressure).foregroundStyle(metrics.pressure == "Normal" ? .green : .orange) }.font(.caption)
                Divider()
                HStack { Text("This app's resident memory"); Spacer(); Text(DisplayFormat.bytes(metrics.appResidentBytes)).monospacedDigit() }.font(.caption)
                Text("RAM shows active + wired + compressed memory. Sampling slows when the panel is closed and in Low Power Mode.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        } else {
            Text(enabled ? "Waiting for the first system sample…" : "System monitoring is disabled in Settings.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 20)
        }
    }
    private func metric(_ name: String, icon: String, value: String, fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label(name, systemImage: icon).font(.headline); Spacer(); Text(value).font(.title3.monospacedDigit()) }
            ProgressView(value: min(1, max(0, fraction))).tint(.blue)
        }
    }
}
