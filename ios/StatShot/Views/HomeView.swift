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
            .task {
                await viewModel.loadSubscriptions()
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Alerts", systemImage: "bell.slash")
        } description: {
            Text("Add your first alert to get notified about player stats and game events.")
        } actions: {
            Button("Add Alert") {
                showingAddAlert = true
            }
            .buttonStyle(.borderedProminent)
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
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40)

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
