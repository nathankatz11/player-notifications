import SwiftUI

/// Renders a player avatar with a three-tier URL cascade and a named
/// initials placeholder:
///   1. `storedURL` (backend-resolved headshot, preferred)
///   2. `League.playerHeadshotURL(espnId:league:)` (combiner fallback)
///   3. Colored circle with the player's initials
///
/// Callers size the view with `.frame(...)`; this view fills and clips to a
/// circle internally.
struct PlayerAvatar: View {
    let name: String
    let espnId: String
    let league: League
    let storedURL: String?
    let size: Int

    init(
        name: String,
        espnId: String,
        league: League,
        storedURL: String? = nil,
        size: Int = 96
    ) {
        self.name = name
        self.espnId = espnId
        self.league = league
        self.storedURL = storedURL
        self.size = size
    }

    var body: some View {
        if let stored = storedURL.flatMap(URL.init(string:)) {
            AsyncImage(url: stored) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: combinerFallback
                case .empty: loading
                @unknown default: loading
                }
            }
            .clipShape(Circle())
        } else {
            combinerFallback
        }
    }

    @ViewBuilder
    private var combinerFallback: some View {
        if let url = League.playerHeadshotURL(espnId: espnId, league: league, size: size) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                case .failure: InitialsAvatar(name: name, league: league)
                case .empty: loading
                @unknown default: loading
                }
            }
            .clipShape(Circle())
        } else {
            InitialsAvatar(name: name, league: league)
        }
    }

    private var loading: some View {
        Circle().fill(league.color.opacity(0.10))
    }
}

/// Colored circle with the athlete's initials. Used as the final fallback
/// when no headshot is reachable.
struct InitialsAvatar: View {
    let name: String
    let league: League

    var body: some View {
        Circle()
            .fill(league.color.opacity(0.18))
            .overlay {
                Text(initials(name))
                    .font(.system(.callout, design: .rounded, weight: .bold))
                    .foregroundStyle(league.color.opacity(0.95))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
    }

    private func initials(_ full: String) -> String {
        let parts = full
            .split(whereSeparator: { !$0.isLetter })
            .prefix(2)
        let letters = parts.compactMap { $0.first.map { String($0).uppercased() } }
        return letters.joined()
    }
}
