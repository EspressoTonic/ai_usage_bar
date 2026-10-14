import SwiftUI
import AppKit

struct DashboardView: View {
    @ObservedObject var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Usage Bar").font(.headline)
                    Text("Quota, context & your Mac").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.refreshAll() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Refresh connected providers")
                Button {
                    openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true)
                } label: { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings")
            }.padding(18)
            if store.demo {
                Label("Demo data · no live provider access", systemImage: "flask")
                    .font(.caption).foregroundStyle(.orange).padding(.horizontal, 18).padding(.bottom, 12)
            }
            Picker("View", selection: $store.tab) {
                Text("Usage").tag("usage"); Text("Chats").tag("chats"); Text("System").tag("system")
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 18).padding(.bottom, 14)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch store.tab {
                    case "chats": ContextView(store: store)
                    case "system": SystemView(metrics: store.snapshot.metrics, enabled: store.preferences.monitorSystem || store.demo)
                    default:
                        ForEach(store.snapshot.providers) { ProviderCard(state: $0, onRefresh: { store.refresh($0) }, onConfigure: {
                            openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true)
                        }) }
                    }
                    if let notice = store.notice {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle")
                            Text(notice).font(.caption).textSelection(.enabled)
                            Spacer(minLength: 0)
                            Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                        }.foregroundStyle(.secondary).padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(.horizontal, 18).padding(.bottom, 16)
            }.frame(maxHeight: 470)
            Divider()
            HStack {
                Label("Local by design", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Open dashboard") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
                    Button("Settings") { openWindow(id: "settings"); NSApp.activate(ignoringOtherApps: true) }
                    Divider()
                    Button("Quit AI Usage Bar") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }.frame(width: 420)
            .onAppear { store.visible(true) }.onDisappear { store.visible(false) }
    }
}
