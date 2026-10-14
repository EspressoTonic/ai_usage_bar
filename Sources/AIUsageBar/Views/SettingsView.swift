import SwiftUI
import UsageCore

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var bearer = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connections & preferences").font(.title2).fontWeight(.semibold)
            Text("Providers are off until you enable them. Enabling a provider reads its existing CLI sign-in file and sends usage requests only to that provider.")
                .font(.caption).foregroundStyle(.secondary)
            Form {
                Section("Provider usage") {
                    ForEach(ProviderID.allCases) { provider in
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle(provider.title, isOn: Binding(get: { store.preferences.providers[provider.rawValue]?.enabled ?? false }, set: { store.configure(provider, enabled: $0) }))
                            TextField("CLI sign-in file", text: Binding(get: { store.preferences.providers[provider.rawValue]?.credentialPath ?? "" }, set: { store.changeCredential(provider, path: $0) }))
                                .font(.caption.monospaced())
                            if provider == .gemini {
                                TextField("Google project (optional)", text: Binding(get: { store.preferences.providers[provider.rawValue]?.project ?? "" }, set: {
                                    store.preferences.providers[provider.rawValue]?.project = $0; store.savePreferences()
                                }))
                            }
                        }.padding(.vertical, 4)
                    }
                    Text("Experimental endpoints can change. Expired sign-ins are renewed by their CLI. No browser scraping or automatic credential replacement.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("Chat context") {
                    Toggle("Read local Codex session metadata", isOn: Binding(get: { store.preferences.readLocalSessions }, set: { store.setLocalMonitoring($0) }))
                    Text("Reads bounded metadata from recent desktop/CLI rollout files. Keeps token counts and IDs, not message text. Local metadata alone cannot compact a chat.")
                        .font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Text("Checkpoint threshold")
                        Slider(value: $store.preferences.contextThreshold, in: 50...95, step: 5)
                        Text("\(Int(store.preferences.contextThreshold))%").monospacedDigit().frame(width: 38)
                    }
                    TextField("Existing local app-server", text: $store.preferences.rpcEndpoint)
                    SecureField("Server bearer token (optional, memory only)", text: $bearer)
                    HStack {
                        Button(store.rpcConnected ? "Reconnect" : "Connect") { Task { await store.connectRPC(bearer: bearer) } }.disabled(store.rpcBusy || store.demo)
                        if store.rpcConnected { Button("Disconnect") { store.disconnectRPC() }.disabled(store.rpcBusy) }
                        if store.rpcBusy { ProgressView().controlSize(.small) }
                    }
                    Text("Connect to the server that already owns the chat. The app never starts or resumes a replacement chat for monitoring.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("Efficiency") {
                    Toggle("Monitor CPU and RAM", isOn: $store.preferences.monitorSystem)
                    Picker("Usage refresh", selection: $store.preferences.refreshSeconds) {
                        Text("2 minutes").tag(120.0); Text("5 minutes").tag(300.0); Text("15 minutes").tag(900.0)
                    }
                }
                Section("Touch Bar add-on") {
                    Text("Optional separate download").font(.subheadline).fontWeight(.medium)
                    Text("The BTT preset is built separately. The main app contains no Touch Bar preset, assets or BTT framework.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Repository & installation guide", destination: URL(string: "https://github.com/EspressoTonic/ai_usage_bar")!)
                }
            }.formStyle(.grouped)
            if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.orange) }
        }.padding(20).frame(width: 600, height: 720)
            .onChange(of: store.preferences.monitorSystem) { _ in store.savePreferences() }
            .onChange(of: store.preferences.refreshSeconds) { _ in store.savePreferences() }
            .onChange(of: store.preferences.contextThreshold) { _ in store.savePreferences() }
            .onChange(of: store.preferences.rpcEndpoint) { _ in store.savePreferences() }
    }
}
