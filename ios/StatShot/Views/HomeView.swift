import SwiftUI

struct HomeView: View {
    @State private var viewModel = SubscriptionViewModel()
    @State private var showingAddAlert = false

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading alerts...")
                } else if viewModel.subscriptions.isEmpty {
                    emptyState
                } else {
                    alertGrid
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Empty State

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

    // MARK: - Alert Grid

    private var alertGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.subscriptions) { subscription in
                    AlertCard(subscription: subscription) {
                        Task { await viewModel.toggleSubscription(subscription) }
                    }
                    .contextMenu {
                        Button(subscription.active ? "Pause" : "Resume",
                               systemImage: subscription.active ? "pause.circle" : "play.circle") {
                            Task { await viewModel.toggleSubscription(subscription) }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await viewModel.deleteSubscription(subscription) }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Alert Card

struct AlertCard: View {
    let subscription: Subscription
    let onTap: () -> Void

    private var leagueColor: Color {
        subscription.league.color
    }

    private var isActive: Bool {
        subscription.active
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    // Outer ring
                    Circle()
                        .strokeBorder(
                            leagueColor.opacity(isActive ? 1.0 : 0.25),
                            lineWidth: 5
                        )
                        .frame(width: 90, height: 90)

                    // Inner filled circle
                    Circle()
                        .fill(leagueColor.opacity(isActive ? 0.15 : 0.05))
                        .frame(width: 80, height: 80)

                    // Sport icon
                    Image(systemName: subscription.league.icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(leagueColor.opacity(isActive ? 1.0 : 0.3))
                }
                .padding(.top, 14)

                // Entity name
                Text(subscription.entityName)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.35))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 40)
                    .padding(.top, 8)

                // Trigger badge
                Text(subscription.trigger.shortLabel)
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .foregroundStyle(isActive ? leagueColor : leagueColor.opacity(0.4))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(leagueColor.opacity(isActive ? 0.15 : 0.05))
                    )
                    .padding(.top, 4)

                // League short name
                Text(subscription.league.shortName)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary.opacity(isActive ? 1.0 : 0.4))
                    .padding(.top, 2)
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(white: 0.11))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        leagueColor.opacity(isActive ? 0.2 : 0.06),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(isActive ? 1.0 : 0.6)
    }
}
