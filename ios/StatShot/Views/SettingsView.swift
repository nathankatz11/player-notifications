import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var activeAlertCount: Int = 0
    @State private var notificationsEnabled: Bool = false
    @State private var showingSignOutConfirmation = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                contactSection
                alertsSection
                notificationSection
                aboutSection
            }
            .navigationTitle("Settings")
            .task {
                await loadActiveAlerts()
                await checkNotificationStatus()
                await authViewModel.loadProfile()
            }
            .confirmationDialog(
                "Sign out of StatShot?",
                isPresented: $showingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    authViewModel.signOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll stop receiving alerts until you sign back in.")
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
                    showingSignOutConfirmation = true
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

    // MARK: - Contact Info

    private var contactSection: some View {
        @Bindable var auth = authViewModel
        return Section {
            HStack(spacing: 10) {
                Image(systemName: "message.fill")
                    .foregroundStyle(.green)
                    .frame(width: 20)
                TextField("Phone number for SMS", text: $auth.phone)
                    .keyboardType(.phonePad)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await authViewModel.saveProfile() } }
            }

            HStack(spacing: 10) {
                Image(systemName: "bird")
                    .foregroundStyle(Color(red: 0.11, green: 0.63, blue: 0.95))
                    .frame(width: 20)
                TextField("Default X handle to tag", text: $auth.xHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await authViewModel.saveProfile() } }
            }

            Button {
                Task {
                    await authViewModel.saveProfile()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            } label: {
                Text("Save Contact Info")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!authViewModel.isAuthenticated)
        } header: {
            Text("Contact Info")
        } footer: {
            Text("Used for SMS alerts and X tagging. The X handle can be yours or a friend's.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Alerts

    private var alertsSection: some View {
        Section("Alerts") {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                Text("Active Alerts")
                Spacer()
                Text("\(activeAlertCount)")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
