import SwiftUI
import UsageCore

struct ContextView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.snapshot.sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Choose a chat to monitor").font(.headline)
                    Text("Enable bounded local Codex metadata in Settings, or connect to an existing local app-server.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                Picker("Selected chat", selection: Binding(get: { store.snapshot.selectedChatID ?? "" }, set: { store.selectChat($0) })) {
                    ForEach(store.snapshot.sessions) { chat in Text("\(String(chat.title.prefix(22))) · \(chat.id.prefix(6))").tag(chat.id) }
                }
                if let chat = store.snapshot.selectedChat {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(chat.title).font(.headline).lineLimit(1)
                                Text(chat.client).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(chat.contextPercent.map { "\(Int($0))%" } ?? "—").font(.title2.monospacedDigit()).fontWeight(.semibold)
                        }
                        if let percent = chat.contextPercent { ProgressView(value: percent, total: 100).tint(percent >= store.preferences.contextThreshold ? .orange : .blue) }
                        Text(chat.recommendation(threshold: store.preferences.contextThreshold)).font(.subheadline)
                        Text("Last-turn context estimate · \(DisplayFormat.age(chat.observedAt).lowercased())")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("ID \(chat.id)").font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                        Button { store.compactSelected() } label: { Label("Compact selected chat", systemImage: "arrow.down.right.and.arrow.up.left") }
                            .buttonStyle(.borderedProminent).disabled(store.compactionDisabledReason != nil || store.rpcBusy)
                        if let reason = store.compactionDisabledReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    }.padding(14).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if let operation = store.snapshot.operation {
                Label(operation.message, systemImage: operation.state == "completed" ? "checkmark.circle" : operation.state == "failed" ? "exclamationmark.triangle" : "hourglass")
                    .font(.caption).foregroundStyle(operation.state == "failed" ? .orange : .secondary)
            }
            Text("Context pressure and subscription quota are separate. Compaction does not refill quota.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
