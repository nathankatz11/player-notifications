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

                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(1)
                }
                // If a push tap lands us here (or we're already here), jump to the
                // Alerts tab so HomeView can pick up the pending deep link.
                .onChange(of: DeepLinkCoordinator.shared.pendingSubscriptionId) { _, newValue in
                    if newValue != nil && selectedTab != 0 {
                        selectedTab = 0
                    }
                }
                // When the user finishes signing in, if there's still a pending
                // deep link (because `consumePendingDeepLink` deliberately
                // didn't consume while unauthenticated), force the Alerts tab.
                // This triggers HomeView's `.onChange` observer on the same
                // pendingSubscriptionId, which now has auth and can resolve.
                .onChange(of: authViewModel.isAuthenticated) { _, isAuthed in
                    guard isAuthed,
                          DeepLinkCoordinator.shared.pendingSubscriptionId != nil else { return }
                    if selectedTab != 0 {
                        selectedTab = 0
                    }
                    // Nudge HomeView: re-set the id so its `.onChange` fires
                    // even if the value didn't change. We write the same value
                    // back to retrigger observers.
                    let id = DeepLinkCoordinator.shared.pendingSubscriptionId
                    DeepLinkCoordinator.shared.pendingSubscriptionId = nil
                    DeepLinkCoordinator.shared.pendingSubscriptionId = id
                }
                .task {
                    // Cold-start: the notification tap may have fired before this
                    // view mounted. If a deep link is already pending, switch to
                    // the Alerts tab so HomeView can consume it.
                    if DeepLinkCoordinator.shared.pendingSubscriptionId != nil {
                        selectedTab = 0
                    }
                }

                if let message = AppErrorCoordinator.shared.message {
                    ToastView(message: message)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture {
                            AppErrorCoordinator.shared.clear()
                        }
                }
            }
            .animation(.spring(response: 0.35), value: AppErrorCoordinator.shared.message)
            .onChange(of: AppErrorCoordinator.shared.message) { _, newValue in
                guard newValue != nil else { return }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    AppErrorCoordinator.shared.clear()
                }
            }
        }
    }
}
