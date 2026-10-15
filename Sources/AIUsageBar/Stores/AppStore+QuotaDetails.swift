import Foundation
import SwiftUI
import UserNotifications
import UsageCore

extension AppStore {
    var profileStates: [CodexProfileState] { snapshot.codexProfiles ?? [] }
    var quotaSources: [(id: String, title: String, state: ProviderState)] {
        snapshot.providers.filter(\.enabled).map { ($0.id.rawValue, $0.id.title, $0) } +
        profileStates.filter { $0.state.enabled }.map { ($0.id, "Codex · " + $0.label, $0.state) }
    }
    var menuQuotaText: String? {
        guard let selection = preferences.menuQuota else { return nil }
        let source = quotaSources.first { $0.id == selection.source }
        let prefix: String
        switch source?.state.id { case .codex: prefix = "C"; case .claude: prefix = "Cl"; case .gemini: prefix = "G"; case .antigravity: prefix = "A"; case nil: prefix = "Q" }
        guard let state = source?.state, let percent = selection.percentage(in: state) else { return prefix + " —" }
        return prefix + " " + String(percent) + "%"
    }
    var menuQuotaHelp: String {
        guard let selection = preferences.menuQuota else { return "AI Usage Bar" }
        guard let source = quotaSources.first(where: { $0.id == selection.source }),
              let window = source.state.snapshot?.windows.first(where: { $0.id == selection.window }) else { return "Selected quota unavailable" }
        return source.title + " · " + window.label + " remaining"
    }
    func addProfile(_ profile: CodexProfile) throws {
        guard !demo, (preferences.codexProfiles ?? []).count < 8 else { throw BridgeError("At most eight Codex sources are supported.") }
        try profile.validate()
        var value = profile; value.enabled = false
        preferences.codexProfiles = (preferences.codexProfiles ?? []) + [value]
        snapshot.codexProfiles = profileStates + [CodexProfileState(profile: value)]
        savePreferences(); publish()
    }
    func setProfileEnabled(_ id: String, enabled: Bool) {
        guard !demo, let index = preferences.codexProfiles?.firstIndex(where: { $0.id == id }) else { return }
        cancelProfileRead()
        preferences.codexProfiles?[index].enabled = enabled
        if let profile = preferences.codexProfiles?[index], let stateIndex = snapshot.codexProfiles?.firstIndex(where: { $0.id == id }) {
            snapshot.codexProfiles?[stateIndex] = CodexProfileState(profile: profile)
        }
        alerts.clear(); savePreferences(); publish()
        if enabled { refreshProfile(id) }
    }
    func removeProfile(_ id: String) {
        guard !demo else { return }
        cancelProfileRead(); alerts.clear()
        preferences.codexProfiles?.removeAll { $0.id == id }; snapshot.codexProfiles?.removeAll { $0.id == id }
        history.prune(sources: Set(ProviderID.allCases.map(\.rawValue) + (preferences.codexProfiles ?? []).map(\.id)))
        saveHistory(); savePreferences(); publish()
    }
    private func cancelProfileRead() {
        profileGeneration += 1; profileTask?.cancel(); profileTask = nil; profileQueue = []
        for index in (snapshot.codexProfiles ?? []).indices { snapshot.codexProfiles?[index].state.refreshing = false }
    }
    private func updateProfile(_ id: String, _ mutation: (inout ProviderState) -> Void) {
        if let index = snapshot.codexProfiles?.firstIndex(where: { $0.id == id }) { mutation(&snapshot.codexProfiles![index].state) }
    }
    func refreshNextProfile(manual: Bool) {
        if manual {
            profileQueue = profileStates.filter { $0.state.enabled }.map(\.id)
            startQueuedProfile(); return
        }
        guard profileTask == nil else { return }
        let candidate = profileStates.filter { $0.state.enabled && ($0.state.nextAttempt ?? .distantPast) <= Date() }
            .sorted { ($0.state.lastAttempt ?? .distantPast) < ($1.state.lastAttempt ?? .distantPast) }
            .first { Date().timeIntervalSince($0.state.lastAttempt ?? .distantPast) >= 15 }
        if let candidate { refreshProfile(candidate.id) }
    }
    private func startQueuedProfile() {
        guard profileTask == nil else { return }
        while !profileQueue.isEmpty {
            let id = profileQueue.removeFirst()
            guard let state = profileStates.first(where: { $0.id == id && $0.state.enabled }),
                  Date().timeIntervalSince(state.state.lastAttempt ?? .distantPast) >= 15 else { continue }
            refreshProfile(id); break
        }
    }
    func refreshProfile(_ id: String) {
        guard !demo, profileTask == nil, let profile = preferences.codexProfiles?.first(where: { $0.id == id && $0.enabled }),
              let state = profileStates.first(where: { $0.id == id }), Date().timeIntervalSince(state.state.lastAttempt ?? .distantPast) >= 15 else { return }
        let generation = profileGeneration
        updateProfile(id) { $0.refreshing = true; $0.lastAttempt = Date() }
        profileTask = Task {
            defer {
                if self.profileGeneration == generation {
                    self.profileTask = nil; self.updateProfile(id) { $0.refreshing = false }; self.publish()
                    self.startQueuedProfile()
                }
            }
            do {
                var reading = try await CodexQuotaClient().fetch(profile: profile)
                guard !Task.isCancelled, self.profileGeneration == generation else { return }
                reading.source = profile.location == .ssh ? "Native Codex over SSH · selected CODEX_HOME" : reading.source
                self.profileFailures[id] = 0; self.recordQuota(source: id, reading: reading)
                self.updateProfile(id) { $0.snapshot = reading; $0.error = nil; $0.nextAttempt = Date().addingTimeInterval(max(120, self.preferences.refreshSeconds)) }
            } catch {
                guard !Task.isCancelled, self.profileGeneration == generation else { return }
                self.profileFailures[id, default: 0] += 1
                let failure = error as? ProviderFailure
                let delay = failure?.kind == .transport ? min(900, max(120, self.preferences.refreshSeconds) * pow(2, Double(min(8, self.profileFailures[id, default: 0])))) : 86400
                self.updateProfile(id) { $0.snapshot = nil; $0.error = (error as? ProviderFailure)?.message ?? "Native Codex source could not be read."; $0.nextAttempt = Date().addingTimeInterval(delay) }
            }
        }
    }
    func recordQuota(source: String, reading: ProviderSnapshot) {
        if preferences.keepHistory == true {
            let previous = history
            history.record(source: source, reading: reading)
            if history != previous { saveHistory() }
        }
        guard preferences.notifications == true else { return }
        let events = alerts.observe(source: source, reading: reading, threshold: preferences.lowQuotaThreshold ?? 10)
        for event in events where event == .low || preferences.notifyResets == true {
            let content = UNMutableNotificationContent()
            content.title = event == .low ? "Quota running low" : "Quota window reset"
            content.body = event == .low ? "A monitored quota crossed your remaining-quota threshold. Open AI Usage Bar for details." : "A fresh reading confirmed a new quota window. Open AI Usage Bar for details."
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
    func setHistoryEnabled(_ enabled: Bool) {
        guard !demo else { return }
        preferences.keepHistory = enabled
        if !enabled { history = QuotaHistory(); saveHistory() }
        savePreferences()
    }
    func expireHistory() {
        guard preferences.keepHistory == true, !history.points.isEmpty else { return }
        let count = history.points.count
        history.prune()
        if history.points.count != count { saveHistory() }
    }
    private func saveHistory() {
        guard !demo, persistenceReady else { return }
        let value = history
        Task { do { try await LocalStore.shared.saveHistory(value) } catch { notice = "Quota history could not be encrypted and saved." } }
    }
    func setNotificationsEnabled(_ enabled: Bool) {
        guard !demo, !notificationRequestInProgress else { return }
        alerts.clear()
        if !enabled {
            preferences.notifications = false; savePreferences()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        notificationRequestInProgress = true
        Task {
            defer { notificationRequestInProgress = false }
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                preferences.notifications = granted
                if !granted { notice = "Notifications are disabled in macOS. Enable AI Usage Bar in System Settings → Notifications." }
            } catch { preferences.notifications = false; notice = "macOS notification permission could not be requested." }
            savePreferences()
        }
    }
}
