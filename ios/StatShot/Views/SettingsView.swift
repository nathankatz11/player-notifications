import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                subscriptionSection
                notificationSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
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
                    Label("Sign in with Apple", systemImage: "apple.logo")
                }
            }
        }
    }

    private var subscriptionSection: some View {
        Section("Subscription") {
            Button {
                showingPaywall = true
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Upgrade to Premium")
                            .fontWeight(.semibold)
                        Text("Unlimited alerts + SMS delivery")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("$4.99/mo")
                        .fontWeight(.medium)
                        .foregroundStyle(.accent)
                }
            }
        }
    }

    private var notificationSection: some View {
        Section("Notifications") {
            Button("Open Notification Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Build", value: "1")
        }
    }
}
