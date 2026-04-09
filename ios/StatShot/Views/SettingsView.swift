import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var activeAlertCount: Int = 0
    @State private var notificationsEnabled: Bool = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                alertsSection
                notificationSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task {
                await loadActiveAlerts()
                await checkNotificationStatus()
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            if authViewModel.isAuthenticated {
                if let user = authViewModel.currentUser {
                    LabeledContent("Email", value: user.email)
                }

                Button("Sign Out", role: .destructive) {
                    authViewModel.signOut()
                }
            } else {
                Button {
                    Task { await authViewModel.signInWithApple() }
                } label: {
                    Label("Sign In (Test Mode)", systemImage: "person.badge.key")
                }
            }
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        Section("Alerts") {
            HStack {
                Text("Active Alerts")
                Spacer()
                Text("\(activeAlertCount)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        Section("Notifications") {
            HStack {
                Text("Push Notifications")
                Spacer()
                if notificationsEnabled {
                    Text("Enabled")
                        .foregroundStyle(.green)
                } else {
                    Text("Disabled")
                        .foregroundStyle(.red)
                }
            }

            if !notificationsEnabled {
                Button("Enable in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)

            ShareLink(
                item: "Check out StatShot — real-time alerts for the plays that matter! https://statshot.app"
            ) {
                Label("Share StatShot", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Data

    private func loadActiveAlerts() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        do {
            let subs = try await APIService.shared.getSubscriptions(userId: userId)
            activeAlertCount = subs.filter(\.active).count
        } catch {
            activeAlertCount = 0
        }
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }
}
