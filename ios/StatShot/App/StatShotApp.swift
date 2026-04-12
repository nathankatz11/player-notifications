import SwiftUI

@main
struct StatShotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
    @State private var selectedTab: Int = 0

    var body: some View {
        if authViewModel.isLoading && !authViewModel.isAuthenticated {
            ProgressView("Setting up...")
        } else {
            ZStack(alignment: .top) {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .tabItem {
                            Label("Alerts", systemImage: "bell.fill")
                        }
                        .tag(0)

                    ScoreFeedView()
                        .tabItem {
                            Label("Scores", systemImage: "sportscourt.fill")
                        }
                        .tag(1)

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(2)
                }
                // If a push tap lands us here (or we're already here), jump to the
                // Alerts tab so HomeView can pick up the pending deep link.
                .onChange(of: DeepLinkCoordinator.shared.pendingSubscriptionId) { _, newValue in
                    if newValue != nil && selectedTab != 0 {
                        selectedTab = 0
                    }
                }
                .task {
                    // Cold-start: the notification tap may have fired before this
                    // view mounted. If a deep link is already pending, switch to
                    // the Alerts tab so HomeView can consume it.
                    if DeepLinkCoordinator.shared.pendingSubscriptionId != nil {
                        selectedTab = 0
                    }
                }

                if let message = DeepLinkCoordinator.shared.toastMessage {
                    ToastView(message: message)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35), value: DeepLinkCoordinator.shared.toastMessage)
            .onChange(of: DeepLinkCoordinator.shared.toastMessage) { _, newValue in
                guard newValue != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    DeepLinkCoordinator.shared.clearToast()
                }
            }
        }
    }
}
