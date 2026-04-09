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
                            Label("No Games", systemImage: "sportscourt")
                        } description: {
                            Text("No \(viewModel.selectedLeague.displayName) games found.")
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
                viewModel.startAutoRefreshIfNeeded()
            }
            .onDisappear {
                viewModel.stopAutoRefresh()
            }
        }
    }

    private var leaguePicker: some View {
        Picker("League", selection: $viewModel.selectedLeague) {
            ForEach(League.allCases) { league in
                Text(league.displayName).tag(league)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var gamesList: some View {
        List(viewModel.games) { game in
            GameRow(game: game, league: viewModel.selectedLeague)
        }
        .listStyle(.plain)
    }
}

// MARK: - Game Row

struct GameRow: View {
    let game: LiveGame
    let league: League

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer()
                statusBadge
                Spacer()
            }

            HStack {
                teamColumn(
                    abbreviation: game.awayTeam?.abbreviation ?? "—",
                    name: game.awayTeam?.team ?? "Away",
                    score: game.awayTeam?.score ?? "0"
                )

                Text("@")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                teamColumn(
                    abbreviation: game.homeTeam?.abbreviation ?? "—",
                    name: game.homeTeam?.team ?? "Home",
                    score: game.homeTeam?.score ?? "0"
                )
            }
        }
        .padding(.vertical, 6)
    }

    private func teamLogoURL(abbreviation: String) -> URL? {
        let abbr = abbreviation.lowercased()
        return URL(string: "https://a.espncdn.com/i/teamlogos/\(league.espnSport)/500/\(abbr).png")
    }

    private func teamColumn(abbreviation: String, name: String, score: String) -> some View {
        VStack(spacing: 4) {
            AsyncImage(url: teamLogoURL(abbreviation: abbreviation)) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                Text(abbreviation)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            Text(abbreviation)
                .font(.headline)
            Text(score)
                .font(.title2.bold())
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusBadge: some View {
        Text(game.statusText)
            .font(.caption.bold())
            .foregroundStyle(game.isLive ? .red : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                game.isLive
                    ? Color.red.opacity(0.1)
                    : Color.secondary.opacity(0.1),
                in: Capsule()
            )
    }
}
