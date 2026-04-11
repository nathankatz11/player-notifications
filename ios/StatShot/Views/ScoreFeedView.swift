import SwiftUI

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
        switch status {
        case "in":
            if let clock, !clock.isEmpty, let period {
                return "\(clock) - P\(period)"
            }
            return "Live"
        case "post":
            return "Final"
        case "pre":
            return "Upcoming"
        default:
            return status.capitalized
        }
    }

    var isLive: Bool {
        status == "in"
    }
}

struct Competitor: Codable {
    let team: String
    let abbreviation: String
    let score: String
    let homeAway: String
}

// MARK: - ViewModel

@MainActor
@Observable
final class ScoreFeedViewModel {
    var games: [LiveGame] = []
    var isLoading = false
    var selectedLeague: League = .nba
    var errorMessage: String?

    private var autoRefreshTask: Task<Void, Never>?

    var hasLiveGames: Bool {
        games.contains { $0.isLive }
    }

    func loadScores() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let url = URL(string: "https://backend-tau-ten-58.vercel.app/api/scores/\(selectedLeague.rawValue)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(ScoresResponse.self, from: data)
            games = decoded.games
        } catch {
            errorMessage = error.localizedDescription
            games = []
        }
    }

    func startAutoRefreshIfNeeded() {
        stopAutoRefresh()
        guard hasLiveGames else { return }

        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await loadScores()
                if !hasLiveGames { break }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}

// MARK: - View

struct ScoreFeedView: View {
    @State private var viewModel = ScoreFeedViewModel()
    @State private var selectedGame: LiveGame?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                leaguePicker

                Group {
                    if viewModel.isLoading && viewModel.games.isEmpty {
                        ProgressView("Loading scores...")
                            .frame(maxHeight: .infinity)
                    } else if let errorMessage = viewModel.errorMessage, viewModel.games.isEmpty {
                        ContentUnavailableView {
                            Label("Unable to Load", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Retry") {
                                Task { await viewModel.loadScores() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else if viewModel.games.isEmpty {
                        ContentUnavailableView {
                            Label("No Games", systemImage: viewModel.selectedLeague.icon)
                        } description: {
                            Text("No \(viewModel.selectedLeague.displayName) games today. Check back on game day!")
                        }
                    } else {
                        gamesList
                    }
                }
            }
            .navigationTitle("Scores")
            .task(id: viewModel.selectedLeague) {
                await viewModel.loadScores()
                viewModel.startAutoRefreshIfNeeded()
            }
            .refreshable {
                await viewModel.loadScores()
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                viewModel.startAutoRefreshIfNeeded()
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
            .sheet(item: $selectedGame) { game in
                GameDetailSheet(game: game, league: viewModel.selectedLeague)
            }
        }
    }

    private var leaguePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(League.allCases) { league in
                    Button {
                        viewModel.selectedLeague = league
                    } label: {
                        HStack(spacing: 6) {
                            AsyncImage(url: league.leagueLogoURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 18, height: 18)
                                default:
                                    Image(systemName: league.icon)
                                        .font(.system(size: 13))
                                        .frame(width: 18, height: 18)
                                }
                            }
                            Text(league.shortName)
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            viewModel.selectedLeague == league
                                ? league.color
                                : Color.clear,
                            in: Capsule()
                        )
                        .foregroundStyle(
                            viewModel.selectedLeague == league
                                ? .white
                                : .secondary
                        )
                        .overlay(
                            viewModel.selectedLeague == league
                                ? nil
                                : Capsule().strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var gamesList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.games) { game in
                    GameRow(game: game, league: viewModel.selectedLeague)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedGame = game
                        }
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }
    }
}

// MARK: - Game Row

struct GameRow: View {
    let game: LiveGame
    let league: League

    @State private var isPulsing = false

    private var awayScore: Int { Int(game.awayTeam?.score ?? "0") ?? 0 }
    private var homeScore: Int { Int(game.homeTeam?.score ?? "0") ?? 0 }
    private var isTied: Bool { awayScore == homeScore }

    var body: some View {
        HStack(spacing: 12) {
            // Away side: logo + abbr + score
            teamSide(
                abbreviation: game.awayTeam?.abbreviation ?? "—",
                score: game.awayTeam?.score ?? "0",
                isWinner: isTied || awayScore > homeScore,
                trailing: true
            )

            Text("—")
                .font(.title3)
                .foregroundStyle(.quaternary)

            // Home side: score + abbr + logo
            teamSide(
                abbreviation: game.homeTeam?.abbreviation ?? "—",
                score: game.homeTeam?.score ?? "0",
                isWinner: isTied || homeScore > awayScore,
                trailing: false
            )

            // Status on right edge
            statusBadge
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .opacity(game.status == "post" ? 0.7 : 1.0)
        .onAppear {
            if game.isLive {
                isPulsing = true
            }
        }
    }

    private func teamLogoURL(abbreviation: String) -> URL? {
        let abbr = abbreviation.lowercased()
        return URL(string: "https://a.espncdn.com/i/teamlogos/\(league.espnSport)/500/\(abbr).png")
    }

    /// A single team side. `trailing` means the score is on the trailing edge (away team layout: logo abbr score).
    /// When `trailing` is false, layout is: score abbr logo (home team).
    @ViewBuilder
    private func teamSide(abbreviation: String, score: String, isWinner: Bool, trailing: Bool) -> some View {
        HStack(spacing: 8) {
            if trailing {
                teamLogo(abbreviation: abbreviation)
                Text(abbreviation)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 4)
                Text(score)
                    .font(.title2.bold())
                    .foregroundStyle(isWinner ? .primary : .secondary)
                    .monospacedDigit()
                    .fixedSize()
            } else {
                Text(score)
                    .font(.title2.bold())
                    .foregroundStyle(isWinner ? .primary : .secondary)
                    .monospacedDigit()
                    .fixedSize()
                Spacer(minLength: 4)
                Text(abbreviation)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                teamLogo(abbreviation: abbreviation)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func teamLogo(abbreviation: String) -> some View {
        AsyncImage(url: teamLogoURL(abbreviation: abbreviation)) { image in
            image
                .resizable()
                .scaledToFit()
        } placeholder: {
            Text(abbreviation)
                .font(.caption2.bold())
                .foregroundStyle(.tertiary)
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private var statusColor: Color {
        switch game.status {
        case "in": return .red
        case "pre": return .blue
        default: return .secondary
        }
    }

    private var statusBadge: some View {
        VStack(spacing: 2) {
            if game.isLive {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                    .opacity(isPulsing ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 1).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
            }

            Text(game.statusText)
                .font(.caption2.bold())
                .foregroundStyle(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - Game Detail Sheet

struct GameDetailSheet: View {
    let game: LiveGame
    let league: League

    @Environment(\.dismiss) private var dismiss
    @State private var showingAddAlert = false
    @State private var showingFollowPlayer = false

    private func teamLogoURL(abbreviation: String) -> URL? {
        let abbr = abbreviation.lowercased()
        return URL(string: "https://a.espncdn.com/i/teamlogos/\(league.espnSport)/500/\(abbr).png")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Status
                Text(game.statusText)
                    .font(.headline)
                    .foregroundStyle(game.isLive ? .red : .secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        game.isLive
                            ? Color.red.opacity(0.1)
                            : Color.secondary.opacity(0.1),
                        in: Capsule()
                    )
                    .padding(.top, 8)

                // Teams and score
                HStack(spacing: 20) {
                    // Away team
                    VStack(spacing: 8) {
                        AsyncImage(url: teamLogoURL(abbreviation: game.awayTeam?.abbreviation ?? "")) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Text(game.awayTeam?.abbreviation ?? "—")
                                .font(.title3.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())

                        Text(game.awayTeam?.team ?? "Away")
                            .font(.subheadline.bold())
                            .multilineTextAlignment(.center)

                        Text(game.awayTeam?.score ?? "0")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)

                    Text("@")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    // Home team
                    VStack(spacing: 8) {
                        AsyncImage(url: teamLogoURL(abbreviation: game.homeTeam?.abbreviation ?? "")) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            Text(game.homeTeam?.abbreviation ?? "—")
                                .font(.title3.bold())
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())

                        Text(game.homeTeam?.team ?? "Home")
                            .font(.subheadline.bold())
                            .multilineTextAlignment(.center)

                        Text(game.homeTeam?.score ?? "0")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)

                Spacer()

                VStack(spacing: 12) {
                    // Follow a player button
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

                    // Create Alert button
                    Button {
                        showingAddAlert = true
                    } label: {
                        Label("Create Alert", systemImage: "bell.badge")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.accentColor)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .navigationTitle(game.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddAlert) {
                AddAlertView()
            }
            .sheet(isPresented: $showingFollowPlayer) {
                AddAlertView(initialLeague: league)
            }
        }
    }
}
