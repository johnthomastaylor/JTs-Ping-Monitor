import SwiftUI

@main
struct PingMonitorApp: App {
    @StateObject private var state = AppState()
    @StateObject private var preferences = Preferences()

    var body: some Scene {
        WindowGroup("JT's Ping Monitor") {
            MainWindowView()
                .environmentObject(state)
                .environmentObject(state.statusStore)
                .environmentObject(state.statsStore)
                .environmentObject(preferences)
                .task { state.start(preferences: preferences) }
        }
        .defaultSize(width: 1000, height: 500)

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(state.statusStore)
                .environmentObject(preferences)
        }
    }
}
