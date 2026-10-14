import SwiftUI
import UsageCore

struct ProviderCard: View {
    let state: ProviderState
    let onRefresh: (ProviderID) -> Void
    let onConfigure: () -> Void
    private var tint: Color { state.id == .codex ? .green : (state.id == .gemini || state.id == .antigravity) ? .blue : .orange }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: state.id.symbol).foregroundStyle(tint).frame(width: 22)
                Text(state.id.title).font(.headline)
                Spacer()
                if state.refreshing { ProgressView().controlSize(.small) }
                else if state.enabled {
                    Button { onRefresh(state.id) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                } else { Button("Connect", action: onConfigure).controlSize(.small) }
            }
            if let reading = state.snapshot {
                ForEach(reading.windows) { window in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(window.label).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("\(Int(window.remainingPercent.rounded()))% left").font(.subheadline.monospacedDigit()).fontWeight(.semibold)
                        }
                        ProgressView(value: window.remainingPercent, total: 100).tint(state.error == nil ? tint : .secondary)
                        Text(DisplayFormat.reset(window.resetsAt)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(reading.source).font(.caption2).foregroundStyle(.secondary)
                Text(DisplayFormat.age(reading.capturedAt)).font(.caption2).foregroundStyle(.secondary)
            } else if state.enabled {
                Text(state.refreshing ? "Fetching usage…" : "Waiting for a successful reading").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(state.id == .antigravity ? "Use your existing Antigravity agy sign-in." : "Use your existing CLI sign-in.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = state.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(13).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }
}
