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
