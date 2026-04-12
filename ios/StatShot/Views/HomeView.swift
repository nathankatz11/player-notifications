import SwiftUI

struct HomeView: View {
    @State private var viewModel = SubscriptionViewModel()
    @State private var showingAddAlert = false
    @State private var selectedSubscription: Subscription?
    @State private var alerts: [AlertItem] = []
    @State private var filteredGames: [LeagueGame] = []
    @State private var isLoadingFeed = false
    @State private var selectedGame: LeagueGame?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.subscriptions.isEmpty {
                    ProgressView("Loading...")
                        .frame(maxHeight: .infinity)
                } else if viewModel.subscriptions.isEmpty {
                    emptyState
                } else {
                    feedContent
                }
            }
            .navigationTitle("Favorites")
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
            .sheet(item: $selectedGame) { lg in
                GameDetailSheet(game: lg.game, league: lg.league)
            }
            .onChange(of: showingAddAlert) { _, isShowing in
                if !isShowing { Task { await loadAll() } }
            }
            .onChange(of: selectedSubscription) { _, value in
                if value == nil { Task { await loadAll() } }
            }
            .onChange(of: DeepLinkCoordinator.shared.pendingSubscriptionId) { _, newValue in
                guard newValue != nil else { return }
                Task { await consumePendingDeepLink() }
            }
            .task {
                await loadAll()
                await consumePendingDeepLink()
            }
            .refreshable {
                await loadAll()
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Feed

    private var feedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                favoritesStrip
                    .padding(.top, 4)

                if !filteredGames.isEmpty {
                    scoresStrip
                }

                Divider()
                    .padding(.horizontal, 16)

                alertsFeed
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Favorites Strip

    private var favoritesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(viewModel.subscriptions) { subscription in
                    FavoriteChip(subscription: subscription)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            selectedSubscription = subscription
                        }
                        .contextMenu {
                            Button {
                                Task {
                                    await viewModel.toggleSubscription(subscription)
                                }
                            } label: {
                                Label(
                                    subscription.active ? "Pause" : "Resume",
                                    systemImage: subscription.active ? "pause.circle" : "play.circle"
                                )
                            }
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteSubscription(subscription)
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Scores Strip

    private var scoresStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filteredGames) { lg in
                    ScoreTile(game: lg.game, league: lg.league)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedGame = lg
                        }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Alerts Feed

    @ViewBuilder
    private var alertsFeed: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Alerts")
                    .font(.headline)
                Spacer()
                if alerts.isEmpty && !isLoadingFeed {
                    Text("No alerts yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)

            if isLoadingFeed && alerts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if alerts.isEmpty {
                emptyAlertsHint
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(alerts) { alert in
                        AlertFeedCard(alert: alert, subscription: subscription(for: alert))
                            .onTapGesture {
                                guard let sub = subscription(for: alert) else { return }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedSubscription = sub
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyAlertsHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("When your alerts fire, they'll show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 16)
    }

    private func subscription(for alert: AlertItem) -> Subscription? {
        viewModel.subscriptions.first { $0.id == alert.subscriptionId }
    }

    // MARK: - Empty state (no subscriptions)

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
            Text(text).font(.body)
        }
    }

    // MARK: - Data loading

    private func loadAll() async {
        isLoadingFeed = true
        defer { isLoadingFeed = false }
        await viewModel.loadSubscriptions()
        async let alertsTask: Void = loadAlerts()
        async let scoresTask: Void = loadScores()
        _ = await (alertsTask, scoresTask)
    }

    private func loadAlerts() async {
        guard let userId = AuthService.shared.currentUserId else {
            alerts = []
            return
        }
        do {
            let page = try await APIService.shared.getAlertHistory(userId: userId, limit: 50)
            alerts = page.alerts
        } catch {
            // Non-critical — leave previous list in place
        }
    }

    private func loadScores() async {
        // Collect leagues the user has any subscription in. Filter games to
        // those whose home/away team id matches a subscribed team — for
        // team subs that's `entityId`; for player subs it's the `teamId`
        // the backend resolved at creation time (may be nil for older subs).
        let leagues = Set(viewModel.subscriptions.map(\.league))
        let followedTeamIds: Set<String> = Set(
            viewModel.subscriptions.compactMap { sub -> String? in
                switch sub.type {
                case .teamEvent: return sub.entityId
                case .playerStat: return sub.teamId
                }
            }
        )
        guard !leagues.isEmpty, !followedTeamIds.isEmpty else {
            filteredGames = []
            return
        }

        var collected: [LeagueGame] = []
        for league in leagues {
            do {
                let data = try await APIService.shared.fetchScores(league: league.rawValue)
                let decoded = try JSONDecoder().decode(ScoresResponse.self, from: data)
                for game in decoded.games {
                    let ids = game.competitors?.compactMap(\.teamId) ?? []
                    if ids.contains(where: followedTeamIds.contains) {
                        collected.append(LeagueGame(league: league, game: game))
                    }
                }
            } catch {
                // Skip this league on failure — don't block the whole feed.
            }
        }
        // Live games first, then upcoming, then final.
        filteredGames = collected.sorted { a, b in
            rank(a.game.status) < rank(b.game.status)
        }
    }

    private func rank(_ status: String) -> Int {
        switch status {
        case "in": 0
        case "pre": 1
        case "post": 2
        default: 3
        }
    }

    // MARK: - Deep Linking

    @MainActor
    private func consumePendingDeepLink() async {
        guard let pendingId = DeepLinkCoordinator.shared.pendingSubscriptionId else { return }
        guard AuthService.shared.currentUserId != nil else { return }

        if let match = viewModel.subscriptions.first(where: { $0.id == pendingId }) {
            selectedSubscription = match
            _ = DeepLinkCoordinator.shared.consume()
            return
        }

        await viewModel.loadSubscriptions()
        if let match = viewModel.subscriptions.first(where: { $0.id == pendingId }) {
            selectedSubscription = match
        } else {
            DeepLinkCoordinator.shared.reportFailure("This alert's subscription is no longer available.")
        }
        _ = DeepLinkCoordinator.shared.consume()
    }
}

// A game paired with the league it came from, so downstream rendering has
// league context without rebuilding it from an abbreviation.
private struct LeagueGame: Identifiable {
    let league: League
    let game: LiveGame
    var id: String { "\(league.rawValue):\(game.id)" }
}

// MARK: - Favorite Chip

private struct FavoriteChip: View {
    let subscription: Subscription

    private var leagueColor: Color { subscription.league.color }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .strokeBorder(
                        leagueColor.opacity(subscription.active ? 0.8 : 0.25),
                        lineWidth: 2
                    )
                    .frame(width: 62, height: 62)
                avatar
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
            }
            Text(shortName(subscription.entityName))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(subscription.active ? .primary : .secondary)
                .frame(width: 72)
        }
        .opacity(subscription.active ? 1.0 : 0.55)
    }

    // "LeBron James" → "L. James", "New York Mets" → "NYM" (handled by shortName in parent data).
    private func shortName(_ full: String) -> String {
        let parts = full.split(separator: " ")
        guard parts.count >= 2, subscription.type == .playerStat else { return full }
        return "\(parts[0].prefix(1)). \(parts.last ?? "")"
    }

    @ViewBuilder
    private var avatar: some View {
        if subscription.type == .playerStat,
           let url = League.playerHeadshotURL(
                espnId: subscription.entityId,
                league: subscription.league,
                size: 108
           ) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholder
                }
            }
        } else {
            AsyncImage(url: League.teamLogoURL(
                espnId: subscription.entityId,
                league: subscription.league
            )) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: placeholder
                }
            }
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(leagueColor.opacity(0.15))
            .overlay {
                Image(systemName: subscription.league.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(leagueColor.opacity(0.7))
            }
    }
}

// MARK: - Score Tile

private struct ScoreTile: View {
    let game: LiveGame
    let league: League

    private func logoURL(_ abbr: String) -> URL? {
        URL(string: "https://a.espncdn.com/i/teamlogos/\(league.espnSport)/500/\(abbr.lowercased()).png")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            teamRow(game.awayTeam)
            teamRow(game.homeTeam)
            Text(status)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(statusColor)
        }
        .padding(10)
        .frame(width: 180)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .opacity(game.status == "post" ? 0.75 : 1)
    }

    @ViewBuilder
    private func teamRow(_ side: Competitor?) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: logoURL(side?.abbreviation ?? "")) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Circle().fill(.tertiary)
            }
            .frame(width: 20, height: 20)

            Text(side?.abbreviation ?? "—")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Spacer()

            Text(side?.score ?? "—")
                .font(.subheadline.bold())
                .monospacedDigit()
        }
    }

    private var status: String {
        switch game.status {
        case "in":
            if let clock = game.clock, !clock.isEmpty, let p = game.period {
                return "\(clock) · P\(p)"
            }
            return "Live"
        case "post": return "Final"
        case "pre":  return "Upcoming"
        default:     return game.status.capitalized
        }
    }

    private var statusColor: Color {
        switch game.status {
        case "in":  .red
        case "pre": .blue
        default:    .secondary
        }
    }
}

// MARK: - Alert Feed Card

private struct AlertFeedCard: View {
    let alert: AlertItem
    let subscription: Subscription?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
                .frame(width: 42, height: 42)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                if let sub = subscription {
                    HStack(spacing: 6) {
                        Text(sub.entityName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(sub.trigger.shortLabel)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(sub.league.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(sub.league.color.opacity(0.15), in: Capsule())
                    }
                }
                Text(alert.message)
                    .font(.footnote)
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(3)
                Text(alert.sentAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatar: some View {
        if let sub = subscription {
            if sub.type == .playerStat,
               let url = League.playerHeadshotURL(
                    espnId: sub.entityId,
                    league: sub.league,
                    size: 84
               ) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: fallback(color: sub.league.color, icon: sub.league.icon)
                    }
                }
            } else {
                AsyncImage(url: League.teamLogoURL(
                    espnId: sub.entityId,
                    league: sub.league
                )) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default: fallback(color: sub.league.color, icon: sub.league.icon)
                    }
                }
            }
        } else {
            fallback(color: .gray, icon: "bell.fill")
        }
    }

    private func fallback(color: Color, icon: String) -> some View {
        Circle()
            .fill(color.opacity(0.15))
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color.opacity(0.7))
            }
    }
}
