import SwiftUI

@main
struct StatShotApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                ContentView()
                    .environment(authViewModel)
                    .task {
                        authViewModel.checkExistingAuth()
                        NotificationService.shared.requestAuthorization()
                        if !authViewModel.isAuthenticated {
                            await authViewModel.signInWithApple()
                        }
                    }
                    .tint(.orange)
                    .preferredColorScheme(.dark)
            } else {
                OnboardingView {
                    UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                    withAnimation(.easeInOut(duration: 0.4)) {
                        hasSeenOnboarding = true
                    }
                }
                .tint(.orange)
                .preferredColorScheme(.dark)
            }
        }
    }
}

struct ContentView: View {
    @Environment(AuthViewModel.self) private var authViewModel

    var body: some View {
        if authViewModel.isLoading && !authViewModel.isAuthenticated {
            ProgressView("Setting up...")
        } else {
            TabView {
                ScoreFeedView()
                    .tabItem {
                        Label("Scores", systemImage: "sportscourt.fill")
                    }

                HomeView()
                    .tabItem {
                        Label("Alerts", systemImage: "bell.fill")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
        }
    }
}
