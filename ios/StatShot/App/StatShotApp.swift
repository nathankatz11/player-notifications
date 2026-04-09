import SwiftUI

@main
struct StatShotApp: App {
    @State private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(authViewModel)
                .onAppear {
                    NotificationService.shared.requestAuthorization()
                }
        }
    }
}

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        TabView {
            Tab("Alerts", systemImage: "bell.fill") {
                HomeView()
            }

            Tab("History", systemImage: "clock.fill") {
                AlertHistoryView()
            }

            Tab("Settings", systemImage: "gear") {
                SettingsView()
            }
        }
    }
}
