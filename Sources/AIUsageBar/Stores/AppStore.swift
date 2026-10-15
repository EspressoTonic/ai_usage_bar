import SwiftUI
import UsageCore
import UserNotifications

@MainActor final class AppStore: ObservableObject {
    @Published var snapshot = AppSnapshot()
    @Published var preferences = Preferences()
    @Published var notice: String?
    @Published var rpcConnected = false
    @Published var rpcBusy = false
    @Published var allowExternalChatAccess = false // Deliberately resets each launch.
    var persistenceReady = false
    @Published var history = QuotaHistory()
    var profileTask: Task<Void, Never>?
    var profileGeneration = 0
    var profileQueue: [String] = []
    var profileFailures: [String: Int] = [:]
    var alerts = QuotaAlertTracker()
    @Published var notificationRequestInProgress = false
    @Published var tab = "usage"
    let demo: Bool
    private var sampler: SystemSampler?
    private let scanner = SessionScanner()
    private let rpc = CodexRPCClient()
    private var bridge: UnixBridgeServer?
    private var loop: Task<Void, Never>?
    private var providerTasks: [ProviderID: Task<Void, Never>] = [:]
    private var generations: [ProviderID: Int] = [:]
    private var failures: [ProviderID: Int] = [:]
    private var visibleSurfaces = 0
    private var lastScan = Date.distantPast
    private var connectedSessions: [ChatSession] = []
    private var recentOperations: [String: CompactionOperation] = [:]

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            snapshot = DemoContent.snapshot(); preferences.showPace = true; preferences.keepHistory = true
            preferences.menuQuota = MenuQuotaSelection(source: "codex", window: "demo-0")
            if let reading = snapshot.providers.first(where: { $0.id == .codex })?.snapshot {
                for step in 0..<6 {
                    var sample = reading; sample.capturedAt = reading.capturedAt.addingTimeInterval(Double(step - 5) * 1800)
                    sample.windows = reading.windows.map { var window = $0; window.usedPercent = max(0, window.usedPercent - Double(5 - step) * 3); return window }
                    history.record(source: "codex", reading: sample, now: sample.capturedAt)
                }
            }
        }
        let server = UnixBridgeServer { [weak self] request in
            guard let self else { return BridgeResponse(ok: false, message: "App stopped.") }
            return await self.handleBridge(request)
        }
        do { try server.start(); bridge = server }
        catch { notice = error.localizedDescription }
        guard bridge != nil else { return } // A second instance must not start another collector.
        loop = Task { [weak self] in
            await self?.restorePrivateState()
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let delay: UInt64 = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : self.visibleSurfaces > 0 ? 2 : 10
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }
    private func restorePrivateState() async {
        guard !demo else { return }
        do {
            if let prefs = try await LocalStore.shared.loadPreferences(), prefs.schemaVersion == 1 {
                preferences = prefs
                for (id, value) in Preferences().providers where preferences.providers[id] == nil { preferences.providers[id] = value }
            }
            if let cache = try await LocalStore.shared.loadCache(), cache.schemaVersion == 1 {
                let enabled = Set(ProviderID.allCases.filter { preferences.providers[$0.rawValue]?.enabled == true })
                snapshot.providers = cache.restored(enabled: enabled)
            }
            for index in snapshot.providers.indices {
                let enabled = preferences.providers[snapshot.providers[index].id.rawValue]?.enabled == true
                snapshot.providers[index].enabled = enabled
                if !enabled { snapshot.providers[index].snapshot = nil; snapshot.providers[index].error = nil }
            }
            snapshot.codexProfiles = (preferences.codexProfiles ?? []).prefix(8).map { CodexProfileState(profile: $0) }
            if preferences.keepHistory == true, var saved = try await LocalStore.shared.loadHistory() {
                saved.prune(sources: Set(ProviderID.allCases.map(\.rawValue) + (preferences.codexProfiles ?? []).map(\.id)))
                history = saved
            }
            persistenceReady = true
        } catch {
            // No automatic overwrite of unreadable encrypted data and no restored provider authorization.
            preferences = Preferences(); snapshot = AppSnapshot()
            notice = "Private storage could not be opened. Existing data is preserved; settings will not be saved this launch."
        }
    }
    deinit { loop?.cancel(); profileTask?.cancel(); providerTasks.values.forEach { $0.cancel() }; bridge?.stop() }

    func visible(_ shown: Bool) { visibleSurfaces = max(0, visibleSurfaces + (shown ? 1 : -1)) }
    func savePreferences() {
        guard !demo else { return }
        guard persistenceReady else { notice = "Private storage is unavailable; settings have not been saved."; return }
        let value = preferences
        Task {
            do { try await LocalStore.shared.savePreferences(value) }
            catch { notice = "Settings could not be encrypted and saved. No plaintext fallback was used." }
        }
    }
    func configure(_ provider: ProviderID, enabled: Bool) {
        guard !demo else { return }
        alerts.clear()
        preferences.providers[provider.rawValue]?.enabled = enabled
        generations[provider, default: 0] += 1
        providerTasks[provider]?.cancel(); providerTasks[provider] = nil
        update(provider) { $0.enabled = enabled; $0.refreshing = false; $0.error = nil; $0.snapshot = nil; $0.nextAttempt = nil }
        savePreferences(); publish()
        if enabled { refresh(provider) }
    }
    func changeCredential(_ provider: ProviderID, path: String) {
        guard !demo, path != preferences.providers[provider.rawValue]?.credentialPath else { return }
        alerts.clear()
        preferences.providers[provider.rawValue]?.credentialPath = path
        generations[provider, default: 0] += 1
        providerTasks[provider]?.cancel(); providerTasks[provider] = nil
        update(provider) { $0.snapshot = nil; $0.refreshing = false; $0.error = nil }
        savePreferences(); publish()
    }
    func refreshAll() {
        if demo { notice = "Demo mode uses sample data. Start normally to connect providers."; return }
        for provider in ProviderID.allCases { refresh(provider) }
        refreshNextProfile(manual: true)
        Task { await refreshSessions() }
    }
    func refresh(_ provider: ProviderID, automatic: Bool = false) {
        guard !demo, let pref = preferences.providers[provider.rawValue], pref.enabled,
              providerTasks[provider] == nil, let state = snapshot.providers.first(where: { $0.id == provider }) else { return }
        if let last = state.lastAttempt, Date().timeIntervalSince(last) < 15 { return }
        if automatic, let next = state.nextAttempt, next > Date() { return }
        let generation = generations[provider, default: 0]
        update(provider) { $0.refreshing = true; $0.lastAttempt = Date() }
        providerTasks[provider] = Task {
            defer {
                if self.generations[provider, default: 0] == generation {
                    self.providerTasks[provider] = nil; self.update(provider) { $0.refreshing = false }; self.publish()
                }
            }
            do {
                let result = try await ProviderClient().fetch(provider, credentialURL: URL(fileURLWithPath: pref.credentialPath), project: pref.project)
                guard !Task.isCancelled, self.generations[provider, default: 0] == generation else { return }
                self.failures[provider] = 0
                self.recordQuota(source: provider.rawValue, reading: result)
                self.update(provider) { $0.snapshot = result; $0.error = nil; $0.nextAttempt = Date().addingTimeInterval((provider == .antigravity ? max(300, self.preferences.refreshSeconds) : self.preferences.refreshSeconds)) }
            } catch {
                guard !Task.isCancelled, self.generations[provider, default: 0] == generation else { return }
                let failure = error as? ProviderFailure
                self.failures[provider, default: 0] += 1
                let delay = failure?.retryAfter ?? min(900, self.preferences.refreshSeconds * pow(2, Double(self.failures[provider, default: 0])))
                self.update(provider) {
                    if failure?.kind != .transport || failure?.accountKey != $0.snapshot?.accountKey { $0.snapshot = nil }
                    $0.error = error.localizedDescription
                    $0.nextAttempt = Date().addingTimeInterval(failure?.kind == .authentication || failure?.kind == .configuration || failure?.kind == .unsupported ? 86_400 : delay)
                }
            }
        }
    }
    func selectChat(_ id: String?) {
        guard id != snapshot.selectedChatID, id == nil || snapshot.sessions.contains(where: { $0.id == id }) else { return }
        snapshot.selectedChatID = id; snapshot.selectionRevision += 1; publish()
    }
    func setLocalMonitoring(_ enabled: Bool) {
        preferences.readLocalSessions = enabled; savePreferences()
        if !enabled { snapshot.sessions.removeAll { $0.source == .localMetadata }; reconcileSelection(); publish() }
        else { Task { await refreshSessions() } }
    }
    func connectRPC(bearer: String) async {
        guard !demo, !rpcBusy else { return }
        rpcBusy = true; defer { rpcBusy = false }
        snapshot.selectionRevision += 1 // Invalidate captured controls when server ownership changes.
        do {
            try await rpc.connect(endpoint: preferences.rpcEndpoint, bearer: bearer)
            connectedSessions = try await rpc.chats(); rpcConnected = true; notice = nil
        } catch { await rpc.disconnect(); rpcConnected = false; connectedSessions = []; notice = error.localizedDescription }
        await mergeSessions()
    }
    func disconnectRPC() {
        guard !rpcBusy else { return }
        Task { await rpc.disconnect() }; rpcConnected = false; connectedSessions = []
        snapshot.selectionRevision += 1
        snapshot.sessions.removeAll { $0.source == .connectedServer }; reconcileSelection(); publish()
    }
    func refreshSessions() async {
        guard !demo else { return }
        if rpcConnected && !rpcBusy {
            rpcBusy = true
            do { connectedSessions = try await rpc.chats() }
            catch { notice = error.localizedDescription; rpcConnected = false; connectedSessions = []; await rpc.disconnect() }
            rpcBusy = false
        }
        await mergeSessions()
    }
    private func mergeSessions() async {
        var local: [ChatSession] = []
        if preferences.readLocalSessions {
            let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            local = await scanner.scan(root: home.appendingPathComponent("sessions"))
        }
        // Never promote old local context counts into a freshly observed server measurement.
        let connectedIDs = Set(connectedSessions.map(\.id))
        snapshot.sessions = connectedSessions + local.filter { !connectedIDs.contains($0.id) }
        reconcileSelection(); publish()
    }
    private func reconcileSelection() {
        if snapshot.selectedChatID == nil || !snapshot.sessions.contains(where: { $0.id == snapshot.selectedChatID }) {
            snapshot.selectedChatID = snapshot.sessions.first?.id; snapshot.selectionRevision += 1
        }
    }
    func compactSelected() {
        let request = BridgeRequest(command: "compact", chatID: snapshot.selectedChatID,
                                    selectionRevision: snapshot.selectionRevision, requestID: UUID().uuidString)
        let response = handle(request)
        if !response.ok { notice = response.message }
    }
    var compactionDisabledReason: String? {
        CompactionGate.rejection(request: BridgeRequest(command: "compact", chatID: snapshot.selectedChatID,
                                                       selectionRevision: snapshot.selectionRevision, requestID: "ui"), snapshot: snapshot)
    }
    func handleBridge(_ request: BridgeRequest) -> BridgeResponse {
        if let reason = BridgePrivacy.rejection(command: request.command, allowChatAccess: allowExternalChatAccess) {
            return BridgeResponse(ok: false, message: reason)
        }
        var response = handle(request)
        if let value = response.snapshot { response.snapshot = BridgePrivacy.snapshot(value, allowChatAccess: allowExternalChatAccess) }
        return response
    }
    func handle(_ request: BridgeRequest) -> BridgeResponse {
        guard request.version == 1 else { return BridgeResponse(ok: false, message: "Incompatible bridge version.") }
        switch request.command {
        case "status", "capabilities": return BridgeResponse(ok: true, snapshot: snapshot)
        case "refresh":
            if let provider = request.provider { refresh(provider) } else { refreshAll() }
            return BridgeResponse(ok: true, message: "Refresh requested.", snapshot: snapshot)
        case "select":
            guard let id = request.chatID, snapshot.sessions.contains(where: { $0.id == id }) else { return BridgeResponse(ok: false, message: "Chat is unavailable.") }
            selectChat(id); return BridgeResponse(ok: true, snapshot: snapshot)
        case "compact":
            if let id = request.requestID, let op = recentOperations[id] { return BridgeResponse(ok: true, message: op.message, snapshot: snapshot) }
            if let reason = CompactionGate.rejection(request: request, snapshot: snapshot) { return BridgeResponse(ok: false, message: reason, snapshot: snapshot) }
            guard !rpcBusy, let id = request.chatID, let requestID = request.requestID else { return BridgeResponse(ok: false, message: "Wait for the current server request.") }
            rpcBusy = true
            let operation = CompactionOperation(id: requestID, chatID: id, state: "running", message: "Waiting for native compaction completion…")
            snapshot.operation = operation; recentOperations[requestID] = operation; publish()
            Task {
                do {
                    try await self.rpc.compact(chatID: id)
                    self.snapshot.operation = CompactionOperation(id: requestID, chatID: id, state: "completed", message: "The provider confirmed compaction.")
                } catch {
                    self.snapshot.operation = CompactionOperation(id: requestID, chatID: id, state: "failed", message: error.localizedDescription)
                }
                self.recentOperations[requestID] = self.snapshot.operation
                if self.recentOperations.count > 64 { self.recentOperations = [requestID: self.snapshot.operation!] }
                self.rpcBusy = false; self.publish(); await self.refreshSessions()
            }
            return BridgeResponse(ok: true, message: "Compaction requested; check operation status for completion.", snapshot: snapshot)
        default: return BridgeResponse(ok: false, message: "Unknown bridge command.")
        }
    }
    private func update(_ id: ProviderID, _ mutation: (inout ProviderState) -> Void) {
        if let index = snapshot.providers.firstIndex(where: { $0.id == id }) { mutation(&snapshot.providers[index]) }
    }
    private func tick() async {
        guard !demo else { return }
        if preferences.monitorSystem {
            if sampler == nil { sampler = SystemSampler() }
            snapshot.metrics = sampler?.sample()
        } else { sampler = nil; snapshot.metrics = nil }
        for provider in ProviderID.allCases { refresh(provider, automatic: true) }
        refreshNextProfile(manual: false)
        expireHistory()
        if Date().timeIntervalSince(lastScan) >= 30 && (preferences.readLocalSessions || rpcConnected) {
            lastScan = Date(); await refreshSessions()
        }
        snapshot.generatedAt = Date()
    }
    func publish() {
        snapshot.generatedAt = Date()
        guard !demo else { return }
        guard persistenceReady else { return }
        let cache = QuotaCache(providers: snapshot.providers)
        Task {
            do { try await LocalStore.shared.saveCache(cache) }
            catch { notice = "Quota cache could not be encrypted and saved. No plaintext fallback was used." }
        }
    }
}
