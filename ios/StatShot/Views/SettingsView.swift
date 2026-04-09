import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var showingPaywall = false
    @State private var activeAlertCount: Int = 0
    @State private var notificationsEnabled: Bool = false

    private var isPremium: Bool {
        authViewModel.currentUser?.plan == .premium
    }

    private var alertLimit: Int { 3 }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                alertsSection
                subscriptionSection
                notificationSection
                appInfoSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .task {
                await loadActiveAlerts()
                await checkNotificationStatus()
            }
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section {
            if authViewModel.isAuthenticated {
                if let user = authViewModel.currentUser {
                    LabeledContent("Email", value: user.email)
                    LabeledContent("Plan", value: user.plan == .premium ? "Premium" : "Free")
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
        } header: {
            Label("Account", systemImage: "person.circle.fill")
                .foregroundStyle(.blue)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
    }

    // MARK: - Alerts Usage

    private var alertsSection: some View {
        Section {
            HStack {
                Label {
                    Text("Active Alerts")
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.orange)
                }

                Spacer()

                if isPremium {
                    Text("\(activeAlertCount) active")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(activeAlertCount) of \(alertLimit) used")
                        .foregroundStyle(activeAlertCount >= alertLimit ? .red : .secondary)
                }
            }

            if !isPremium {
                ProgressView(value: Double(min(activeAlertCount, alertLimit)), total: Double(alertLimit))
                    .tint(activeAlertCount >= alertLimit ? .red : Color.accentColor)
            }
        } header: {
            Label("Usage", systemImage: "chart.bar.fill")
                .foregroundStyle(.orange)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
    }

    // MARK: - Subscription / Upgrade

    private var subscriptionSection: some View {
        Section {
            if isPremium {
                HStack(spacing: 12) {
                    Image(systemName: "star.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Premium Active")
                            .fontWeight(.semibold)
                        Text("Unlimited alerts + SMS delivery")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    upgradeCard
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } header: {
            Label("Subscription", systemImage: "star.fill")
                .foregroundStyle(.yellow)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
    }

    private var upgradeCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 4) {
                Text("Upgrade to Premium")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Unlimited alerts + SMS delivery")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            Text("$4.99/mo")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.7), .purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Notifications

    private var notificationSection: some View {
        Section {
            HStack {
                Label {
                    Text("Push Notifications")
                } icon: {
                    Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                        .foregroundStyle(notificationsEnabled ? .green : .red)
                }

                Spacer()

                if notificationsEnabled {
                    Text("Enabled")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    Text("Disabled")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }

            if !notificationsEnabled {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Enable in Settings", systemImage: "gear")
                }
            }
        } header: {
            Label("Notifications", systemImage: "bell.badge.fill")
                .foregroundStyle(.green)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
    }

    // MARK: - App Info

    private var appInfoSection: some View {
        Section {
            LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")

            ShareLink(
                item: "Check out StatShot - real-time sports alerts for the plays that matter! https://statshot.app"
            ) {
                Label("Share StatShot", systemImage: "square.and.arrow.up")
            }

            Link(destination: URL(string: "https://apps.apple.com/app/id0000000000")!) {
                Label("Rate on App Store", systemImage: "star.bubble")
            }
        } header: {
            Label("About", systemImage: "info.circle.fill")
                .foregroundStyle(.purple)
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
        }
    }

    // MARK: - Data Loading

    private func loadActiveAlerts() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        do {
            let subscriptions = try await APIService.shared.getSubscriptions(userId: userId)
            activeAlertCount = subscriptions.filter(\.active).count
        } catch {
            activeAlertCount = 0
        }
    }

    private func checkNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsEnabled = settings.authorizationStatus == .authorized
    }
}
