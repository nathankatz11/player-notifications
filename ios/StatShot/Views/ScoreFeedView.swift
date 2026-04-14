import SwiftUI

// NOTE: The standalone Scores tab was removed; the app is now 2 tabs
// (Alerts + Settings). This file retains:
//   - Score response models (used by HomeView's filtered scores strip)
//   - GameDetailSheet (presented from HomeView when a ScoreTile is tapped)
// The filename is kept as `ScoreFeedView.swift` to avoid pbxproj churn.
// The former `ScoreFeedView`, `ScoreFeedViewModel`, and `GameRow` types
// have been deleted.

// MARK: - Models

struct ScoresResponse: Codable {
    let league: String
    let games: [LiveGame]
}

struct LiveGame: Codable, Identifiable {
    let id: String
    let name: String
    let status: String
    let clock: String?
    let period: Int?
    let competitors: [Competitor]?

    var homeTeam: Competitor? {
        competitors?.first { $0.homeAway == "home" }
    }

    var awayTeam: Competitor? {
        competitors?.first { $0.homeAway == "away" }
    }

    var statusText: String {
        statusText(for: nil)
    }

    /// League-aware status string. Baseball has no game clock, so we
    /// render "Top 5" / "Bot 5" instead of the wall-clock time ESPN
    /// returns in `displayClock`. Soccer uses minutes elapsed.
    func statusText(for league: League?) -> String {
        switch status {
        case "in":
            switch league {
            case .mlb:
                if let period { return baseballHalfInning(period: period) }
                return "Live"
            case .mls:
                if let clock, !clock.isEmpty { return clock }
                return "Live"
            default:
                if let clock, !clock.isEmpty, let period {
                    return "Q\(period) \(clock)"
                }
                return "Live"
            }
        case "post":
            return "Final"
        case "pre":
            return "Upcoming"
        default:
            return status.capitalized
        }
    }

    private func baseballHalfInning(period: Int) -> String {
        let inning = (period + 1) / 2
        return period % 2 == 1 ? "Top \(inning)" : "Bot \(inning)"
    }

    var isLive: Bool {
        status == "in"
    }
}

struct Competitor: Codable {
    let teamId: String?
    let team: String
    let abbreviation: String
    let score: String
    let homeAway: String
}

// MARK: - Game Detail Sheet

struct GameDetailSheet: View {
    let game: LiveGame
    let league: League

    @Environment(\.dismiss) private var dismiss
    @State private var showingFollowPlayer = false
    @State private var relevantSubscriptions: [Subscription] = []
    @State private var selectedSubscription: Subscription?

    private func teamLogoURL(abbreviation: String) -> URL? {
        let abbr = abbreviation.lowercased()
        return URL(string: "https://a.espncdn.com/i/teamlogos/\(league.espnSport)/500/\(abbr).png")
    }

    private var gameContext: GameContext? {
        guard let away = game.awayTeam, let home = game.homeTeam,
              let awayId = away.teamId, let homeId = home.teamId else {
            return nil
        }
        return GameContext(
            league: league,
            away: GameContext.Side(teamId: awayId, teamName: away.team, teamAbbr: away.abbreviation),
            home: GameContext.Side(teamId: homeId, teamName: home.team, teamAbbr: home.abbreviation)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusBadge
                    scoreHeader
                    if !relevantSubscriptions.isEmpty {
                        yourAlertsSection
                    }
                    followAction
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
            }
            .navigationTitle(game.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingFollowPlayer) {
                if let ctx = gameContext {
                    AddAlertView(gameContext: ctx)
                } else {
                    AddAlertView(initialLeague: league)
                }
            }
            .sheet(item: $selectedSubscription) { sub in
                AlertDetailView(subscription: sub) {
                    relevantSubscriptions.removeAll { $0.id == sub.id }
                }
            }
            .task {
                await loadRelevantSubscriptions()
            }
            .onChange(of: showingFollowPlayer) { _, isShowing in
                if !isShowing {
                    Task { await loadRelevantSubscriptions() }
                }
            }
        }
    }

    private var statusBadge: some View {
        Text(game.statusText(for: league))
            .font(.headline)
            .foregroundStyle(game.isLive ? .red : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                game.isLive ? Color.red.opacity(0.1) : Color.secondary.opacity(0.1),
                in: Capsule()
            )
    }

    private var scoreHeader: some View {
        HStack(spacing: 20) {
            sideColumn(
                abbr: game.awayTeam?.abbreviation,
                name: game.awayTeam?.team,
                score: game.awayTeam?.score
            )
            Text("@").font(.title3).foregroundStyle(.secondary)
            sideColumn(
                abbr: game.homeTeam?.abbreviation,
                name: game.homeTeam?.team,
                score: game.homeTeam?.score
            )
        }
    }

    private func sideColumn(abbr: String?, name: String?, score: String?) -> some View {
        VStack(spacing: 8) {
            AsyncImage(url: teamLogoURL(abbreviation: abbr ?? "")) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Text(abbr ?? "—").font(.title3.bold()).foregroundStyle(.secondary)
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())

            Text(name ?? "—")
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)

            Text(score ?? "0")
                .font(.system(size: 40, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }

    private var yourAlertsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your alerts in this game")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            ForEach(relevantSubscriptions) { sub in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedSubscription = sub
                } label: {
                    HStack(spacing: 12) {
                        avatar(for: sub)
                            .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.entityName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(sub.trigger.displayName)
                                .font(.caption)
                                .foregroundStyle(sub.league.color)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func avatar(for sub: Subscription) -> some View {
        if sub.type == .playerStat {
            PlayerAvatar(
                name: sub.entityName,
                espnId: sub.entityId,
                league: sub.league,
                storedURL: sub.photoUrl,
                size: 72
            )
        } else {
            AsyncImage(url: League.teamLogoURL(espnId: sub.entityId, league: sub.league)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Circle().fill(sub.league.color.opacity(0.2))
            }
        }
    }

    private var followAction: some View {
        Button {
            showingFollowPlayer = true
        } label: {
            Label("Follow a Player from This Game", systemImage: "person.badge.plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.accentColor)
    }

    @MainActor
    private func loadRelevantSubscriptions() async {
        guard let userId = AuthService.shared.currentUserId else {
            relevantSubscriptions = []
            return
        }
        let awayId = game.awayTeam?.teamId
        let homeId = game.homeTeam?.teamId
        guard awayId != nil || homeId != nil else { return }

        do {
            let all = try await APIService.shared.getSubscriptions(userId: userId)
            relevantSubscriptions = all.filter { sub in
                guard sub.active, sub.league == league else { return false }
                switch sub.type {
                case .teamEvent:
                    return sub.entityId == awayId || sub.entityId == homeId
                case .playerStat:
                    return sub.teamId == awayId || sub.teamId == homeId
                }
            }
        } catch {
            relevantSubscriptions = []
        }
    }
}
