import SwiftUI

struct HomeView: View {
    @State private var viewModel = SubscriptionViewModel()
    @State private var showingAddAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading alerts...")
                } else if viewModel.subscriptions.isEmpty {
                    emptyState
                } else {
                    subscriptionList
                }
            }
            .navigationTitle("My Alerts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddAlert = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddAlert) {
                AddAlertView()
            }
            .onChange(of: showingAddAlert) { _, isShowing in
                if !isShowing {
                    Task { await viewModel.loadSubscriptions() }
                }
            }
            .task {
                await viewModel.loadSubscriptions()
            }
            .refreshable {
                await viewModel.loadSubscriptions()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            Image(systemName: "bell.badge")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("Get Started")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 16) {
                stepRow(number: 1, text: "Browse scores", icon: "sportscourt")
                stepRow(number: 2, text: "Pick a team", icon: "person.2.fill")
                stepRow(number: 3, text: "Choose what to track", icon: "bell.fill")
            }
            .padding(.horizontal, 32)

            Button {
                showingAddAlert = true
            } label: {
                Text("Create Your First Alert")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }

    private func stepRow(number: Int, text: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor, in: Circle())

            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(text)
                .font(.body)
        }
    }

    private var subscriptionList: some View {
        List {
            ForEach(viewModel.subscriptions) { subscription in
                SubscriptionRow(subscription: subscription)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.deleteSubscription(subscription) }
                        }
                    }
            }
        }
    }
}

struct SubscriptionRow: View {
    let subscription: Subscription

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: subscription.league.icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.accentColor, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(subscription.entityName)
                    .font(.headline)

                Text("\(subscription.trigger.displayName) • \(subscription.league.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !subscription.active {
                Text("Paused")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.1), in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
