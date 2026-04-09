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
            HomeView()
                .tabItem {
                    Label("Alerts", systemImage: "bell.fill")
                }

            AlertHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
