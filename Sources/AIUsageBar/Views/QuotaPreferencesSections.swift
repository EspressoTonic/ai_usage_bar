import SwiftUI
import UsageCore

struct QuotaPreferencesSections: View {
    @ObservedObject var store: AppStore
    @State private var addingSource = false
    private var selection: Binding<MenuQuotaSelection?> {
        Binding(get: { store.preferences.menuQuota }, set: { store.preferences.menuQuota = $0; store.savePreferences() })
    }
    private var selectedAvailable: Bool {
        guard let selected = store.preferences.menuQuota else { return true }
        return store.quotaSources.contains { source in source.id == selected.source && source.state.snapshot?.windows.contains { $0.id == selected.window } == true }
    }
    var body: some View {
        Section("Named Codex sources") {
            ForEach(store.profileStates) { profile in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Toggle(profile.label, isOn: Binding(get: { profile.state.enabled }, set: { store.setProfileEnabled(profile.id, enabled: $0) }))
                        Button("Remove") { store.removeProfile(profile.id) }.disabled(store.demo)
                    }
                    if let config = store.preferences.codexProfiles?.first(where: { $0.id == profile.id }) {
                        Text((config.location == .ssh ? config.host + ":" : "Local · ") + config.home)
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            Button("Add Codex source…") { addingSource = true }.disabled(store.demo || store.profileStates.count >= 8)
            Text("Use separate CODEX_HOME directories for personal and work accounts. Codex owns authentication, including its keyring. Sources are read serially and do not switch accounts or control chats.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $addingSource) { AddCodexSourceView(store: store) }
        Section("Quota display & history") {
            Picker("Menu bar percentage", selection: selection) {
                Text("Icon only").tag(Optional<MenuQuotaSelection>.none)
                if !selectedAvailable, let selected = store.preferences.menuQuota {
                    Text("Selected quota unavailable").tag(Optional(selected))
                }
                ForEach(store.quotaSources, id: \.id) { source in
                    ForEach(source.state.snapshot?.windows ?? []) { window in
                        Text(source.title + " · " + window.label).tag(Optional(MenuQuotaSelection(source: source.id, window: window.id)))
                    }
                }
            }
            Text("Choose one reported limit after its first successful reading. The menu bar shows a dash when that reading is stale or unavailable.")
                .font(.caption2).foregroundStyle(.secondary)
            Toggle("Show window-average pace estimates", isOn: Binding(get: { store.preferences.showPace == true }, set: { store.preferences.showPace = $0; store.savePreferences() }))
            Toggle("Keep encrypted quota history for up to 7 days", isOn: Binding(get: { store.preferences.keepHistory == true }, set: { store.setHistoryEnabled($0) })).disabled(store.demo)
            Text("At most 1,000 changed readings across all sources. Disabling clears saved history. Charts show the current account and reset window only. Antigravity and native Codex versions without workspace identity do not enter history or alerts.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        Section("Quota notifications") {
            Toggle("Notify when remaining quota crosses a threshold", isOn: Binding(get: { store.preferences.notifications == true }, set: { store.setNotificationsEnabled($0) }))
                .disabled(store.demo || store.notificationRequestInProgress)
            HStack {
                Text("Remaining")
                Slider(value: Binding(get: { store.preferences.lowQuotaThreshold ?? 10 }, set: {
                    store.preferences.lowQuotaThreshold = $0; store.alerts.clear(); store.savePreferences()
                }), in: 5...30, step: 5)
                Text("\(Int(store.preferences.lowQuotaThreshold ?? 10))%").monospacedDigit().frame(width: 36)
            }
            Toggle("Also notify after an observed quota reset", isOn: Binding(get: { store.preferences.notifyResets == true }, set: { store.preferences.notifyResets = $0; store.savePreferences() }))
                .disabled(store.preferences.notifications != true || store.demo)
            Text("The first successful poll establishes a silent baseline. Notifications omit account emails, source names and quota values. Reset alerts need a successful poll after the reset; offline changes are not immediate.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct AddCodexSourceView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var profile = CodexProfile(home: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path)
    @State private var error: String?
    private var valid: Bool { (try? profile.validate()) != nil }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Codex source").font(.title2).fontWeight(.semibold)
            TextField("Label, e.g. Personal or Work", text: $profile.label)
            Picker("Location", selection: $profile.location) { Text("This Mac").tag(CodexProfile.Location.local); Text("SSH server").tag(CodexProfile.Location.ssh) }
            if profile.location == .ssh {
                TextField("Existing SSH alias, e.g. my-server", text: $profile.host)
                Text("Uses your existing SSH configuration, agent and trusted host key. No password prompts or new host-key acceptance. Use your own Unix account.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Absolute CODEX_HOME directory", text: $profile.home).font(.body.monospaced())
            TextField("Absolute Codex executable path", text: $profile.executable).font(.body.monospaced())
            Text("Added sources start disabled. Enable the source after reviewing its paths. Sign in separately with your Codex CLI or codex-account companion.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer(); Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add source") { do { try store.addProfile(profile); dismiss() } catch { self.error = error.localizedDescription } }
                    .keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.textFieldStyle(.roundedBorder).padding(24).frame(width: 510)
            .onChange(of: profile.location) { location in
                profile.home = location == .local ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path : ""
                profile.executable = ""
            }
    }
}
