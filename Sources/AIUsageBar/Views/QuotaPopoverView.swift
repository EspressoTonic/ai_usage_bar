import SwiftUI
import AppKit
import UsageCore

struct QuotaPopoverView: View {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 500

    private var enabledProviders: [ProviderState] {
        store.snapshot.providers.filter(\.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quota remaining").font(.headline)
                    Text("Subscription limits").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.refreshAll() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh quota")
                .help("Refresh connected providers")
                Button { showWindow("settings") } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Settings")
                .help("Manage providers")
            }
            .padding(16)

            if store.demo {
                Label("Demo data", systemImage: "flask")
                    .font(.caption).foregroundStyle(.orange)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }

            if enabledProviders.isEmpty && store.profileStates.allSatisfy({ !$0.state.enabled }) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Connect a provider", systemImage: "terminal")
                        .font(.headline)
                    Text("Choose the CLI accounts whose remaining quota you want to see here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Choose providers") { showWindow("settings") }
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16).padding(.bottom, 16)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(enabledProviders) { state in
                            ProviderCard(state: state, onRefresh: { store.refresh($0) },
                                         onConfigure: { showWindow("settings") }, showPace: store.preferences.showPace == true,
                                         sourceID: state.id.rawValue)
                        }
                        ForEach(store.profileStates.filter { $0.state.enabled }) { profile in
                            ProviderCard(state: profile.state, onRefresh: { _ in store.refreshProfile(profile.id) },
                                         onConfigure: { showWindow("settings") }, title: "Codex · " + profile.label,
                                         showPace: store.preferences.showPace == true,
                                         sourceID: profile.id)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: QuotaContentHeightKey.self,
                                                   value: geometry.size.height)
                        }
                    }
                }
                .frame(height: min(500, max(1, contentHeight)))
                .onPreferenceChange(QuotaContentHeightKey.self) { contentHeight = $0 }
            }

            if let notice = store.notice {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                    Text(notice).lineLimit(3).help(notice)
                    Spacer(minLength: 0)
                    Button { store.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).accessibilityLabel("Dismiss notice")
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 12)
            }

            Divider()
            HStack {
                Button { showWindow("dashboard") } label: {
                    Label("Dashboard", systemImage: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderless)
                .help("Open usage, chats and system monitoring")
                Spacer()
                Menu {
                    Button("Manage providers") { showWindow("settings") }
                    Divider()
                    Button("Quit AI Usage Bar") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("More actions")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(width: 380)
        .onAppear { store.visible(true) }
        .onDisappear { store.visible(false) }
    }

    private func showWindow(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct QuotaContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
