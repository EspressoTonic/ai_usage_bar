import SwiftUI
import UsageCore

struct ProviderCard: View {
    let state: ProviderState
    let onRefresh: (ProviderID) -> Void
    let onConfigure: () -> Void
    var title: String? = nil
    var showPace = false
    var history: QuotaHistory? = nil
    var sourceID: String? = nil
    private var tint: Color { state.id == .codex ? .green : (state.id == .gemini || state.id == .antigravity) ? .blue : .orange }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: state.id.symbol).foregroundStyle(tint).frame(width: 22)
                Text(title ?? state.id.title).font(.headline)
                Spacer()
                if state.refreshing { ProgressView().controlSize(.small) }
                else if state.enabled {
                    Button { onRefresh(state.id) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless)
                } else { Button("Connect", action: onConfigure).controlSize(.small) }
            }
            if let reading = state.snapshot {
                if let identity = reading.identity {
                    VStack(alignment: .leading, spacing: 3) {
                        if let email = identity.email { Text(email).font(.caption).textSelection(.enabled) }
                        if let plan = identity.plan { Text("Plan: " + plan).font(.caption2).foregroundStyle(.secondary) }
                        if let workspace = identity.workspace { Text("Workspace: " + workspace).font(.caption2).foregroundStyle(.secondary) }
                    }
                }
                ForEach(reading.windows) { window in
                    VStack(alignment: .leading, spacing: 6) {
                        QuotaWindowView(window: window, tint: tint, muted: state.error != nil,
                                        capturedAt: reading.capturedAt, showPace: showPace)
                        if let history, let sourceID {
                            QuotaHistoryView(points: history.series(source: sourceID, account: reading.accountKey, window: window), tint: tint)
                        }
                    }
                }
                if let credits = reading.credits {
                    ForEach(credits) { credit in
                        VStack(alignment: .leading, spacing: 2) {
                            if let count = credit.resetCredits { Text("Limit reset credits: \(count)") }
                            else if credit.unlimited == true { Text(credit.label + " credits: unlimited") }
                            else if let balance = credit.balance { Text(credit.label + " credits: " + balance) }
                            else if let available = credit.hasCredits { Text(credit.label + (available ? " credits available" : " credits: none available")) }
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if state.id == .codex && reading.identityVerified == false {
                    Text("Workspace identity unavailable · history and alerts paused for this source.")
                        .font(.caption2).foregroundStyle(.secondary)
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
