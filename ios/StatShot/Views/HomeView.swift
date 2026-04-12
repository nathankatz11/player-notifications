import SwiftUI

struct HomeView: View {
    @State private var viewModel = SubscriptionViewModel()
    @State private var showingAddAlert = false
    @State private var selectedSubscription: Subscription?
    @State private var alertCounts: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("Loading alerts...")
                } else if viewModel.subscriptions.isEmpty {
                    emptyState
                } else {
                    alertList
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
            .sheet(item: $selectedSubscription) { subscription in
                AlertDetailView(subscription: subscription) {
                    viewModel.subscriptions.removeAll { $0.id == subscription.id }
                }
            }
            .onChange(of: showingAddAlert) { _, isShowing in
                if !isShowing {
                    Task {
                        await viewModel.loadSubscriptions()
                        await loadAlertCounts()
                    }
                }
            }
            .onChange(of: selectedSubscription) { _, value in
                if value == nil {
                    Task {
                        await viewModel.loadSubscriptions()
                        await loadAlertCounts()
                    }
                }
            }
            .onChange(of: DeepLinkCoordinator.shared.pendingSubscriptionId) { _, newValue in
                guard newValue != nil else { return }
                Task { await consumePendingDeepLink() }
            }
            .task {
                await viewModel.loadSubscriptions()
                await loadAlertCounts()
                // Cold-start: handle any deep link that arrived before this
                // view mounted (e.g. app launched from a notification tap).
                await consumePendingDeepLink()
            }
            .refreshable {
                await viewModel.loadSubscriptions()
                await loadAlertCounts()
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                stepRow(number: 2, text: "Pick a team or player", icon: "person.fill")
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

    // MARK: - Alert List

    private var alertList: some View {
        List {
            ForEach(viewModel.subscriptions) { subscription in
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    selectedSubscription = subscription
                } label: {
                    AlertRow(
                        subscription: subscription,
                        alertCount: alertCounts[subscription.id] ?? 0
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color(white: 0.11))
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteSubscription(subscription) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        Task { await viewModel.toggleSubscription(subscription) }
                    } label: {
                        Label(
                            subscription.active ? "Pause" : "Resume",
                            systemImage: subscription.active ? "pause.circle" : "play.circle"
                        )
                    }
                    .tint(subscription.active ? .orange : .green)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Deep Linking

    /// Resolves a pending deep-link subscription id (set by
    /// `NotificationService.didReceive`) to a local `Subscription` and opens
    /// the detail sheet. If the subscriptions list hasn't loaded yet (or the
    /// id isn't in it — e.g. a stale subscription), reloads once and retries.
    private func consumePendingDeepLink() async {
        guard let pendingId = DeepLinkCoordinator.shared.pendingSubscriptionId else {
            return
        }

        if let match = viewModel.subscriptions.first(where: { $0.id == pendingId }) {
            _ = DeepLinkCoordinator.shared.consume()
            selectedSubscription = match
            return
        }

        // Not in the map yet — reload and retry once.
        await viewModel.loadSubscriptions()
        if let match = viewModel.subscriptions.first(where: { $0.id == pendingId }) {
            _ = DeepLinkCoordinator.shared.consume()
            selectedSubscription = match
        } else {
            // Subscription couldn't be resolved (deleted?). Surface a toast so
            // the user isn't confused by a silently-dropped tap, then clear the
            // pending id so we don't keep retrying forever.
            DeepLinkCoordinator.shared.reportFailure("This alert's subscription is no longer available.")
            _ = DeepLinkCoordinator.shared.consume()
        }
    }

    // MARK: - Alert Counts

    private func loadAlertCounts() async {
        guard let userId = AuthService.shared.currentUserId else { return }
        do {
            let alerts = try await APIService.shared.getAlertHistory(userId: userId)
            var counts: [String: Int] = [:]
            for alert in alerts {
                counts[alert.subscriptionId, default: 0] += 1
            }
            alertCounts = counts
        } catch {
            // Non-critical — silently ignore
        }
    }
}

// MARK: - Alert Row

struct AlertRow: View {
    let subscription: Subscription
    let alertCount: Int

    private var leagueColor: Color { subscription.league.color }
    private var isActive: Bool { subscription.active }

    var body: some View {
        HStack(spacing: 14) {
            // Avatar: player headshot or team logo
            ZStack {
                Circle()
                    .strokeBorder(leagueColor.opacity(isActive ? 0.8 : 0.25), lineWidth: 2)
                    .frame(width: 52, height: 52)

                avatarImage
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            }

            // Name + trigger
            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.entityName)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.4))
                    .lineLimit(1)

                Text(subscription.trigger.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary.opacity(isActive ? 1.0 : 0.5))
                    .lineLimit(1)
            }

            Spacer()

            // Right side: league badge + alert count + status dot
            VStack(alignment: .trailing, spacing: 4) {
                Text(subscription.league.shortName)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(leagueColor.opacity(isActive ? 1.0 : 0.4))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(leagueColor.opacity(isActive ? 0.15 : 0.06), in: Capsule())

                HStack(spacing: 4) {
                    if alertCount > 0 {
                        Text("\(alertCount)")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                    Circle()
                        .fill(isActive ? leagueColor : Color(white: 0.3))
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.vertical, 6)
        .opacity(isActive ? 1.0 : 0.55)
    }

    @ViewBuilder
    private var avatarImage: some View {
        if subscription.type == .playerStat,
           let url = League.playerHeadshotURL(espnId: subscription.entityId, league: subscription.league, size: 88) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Circle()
                        .fill(leagueColor.opacity(0.15))
                        .overlay {
                            Image(systemName: subscription.league.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(leagueColor.opacity(0.7))
                        }
                }
            }
        } else {
            AsyncImage(url: League.teamLogoURL(espnId: subscription.entityId, league: subscription.league)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Circle()
                        .fill(leagueColor.opacity(0.15))
                        .overlay {
                            Image(systemName: subscription.league.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(leagueColor.opacity(0.7))
                        }
                }
            }
        }
    }
}
