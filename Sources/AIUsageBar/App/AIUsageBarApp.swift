import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main struct AIUsageBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: AppStore
    init() {
        // Start the collector/bridge even before the first popover is opened.
        let instance = AppStore(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
        _store = StateObject(wrappedValue: instance)
    }
    var body: some Scene {
        MenuBarExtra {
            QuotaPopoverView(store: store)
        } label: {
            LaunchIcon()
        }
        .menuBarExtraStyle(.window)
        Window("AI Usage Bar", id: "dashboard") {
            if store.demo && ProcessInfo.processInfo.arguments.contains("--preview-quota") {
                QuotaPopoverView(store: store)
            } else {
                DashboardView(store: store)
            }
        }.windowResizability(.contentSize)
        Window("AI Usage Bar Settings", id: "settings") {
            SettingsView(store: store)
        }.windowResizability(.contentSize)
    }
}

private struct LaunchIcon: View {
    @Environment(\.openWindow) private var openWindow
    @State private var previewOpened = false
    var body: some View {
        Image(systemName: "chart.bar.xaxis")
            .accessibilityLabel("AI Usage Bar")
            .onAppear {
                let arguments = ProcessInfo.processInfo.arguments
                if !previewOpened && (arguments.contains("--preview") || arguments.contains("--preview-quota")) {
                    previewOpened = true
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }
}
