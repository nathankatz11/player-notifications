import Foundation
import SwiftUI

enum League: String, Codable, CaseIterable, Identifiable {
    case nba, nfl, nhl, mlb, ncaafb, ncaamb, mls

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nba: "NBA"
        case .nfl: "NFL"
        case .nhl: "NHL"
        case .mlb: "MLB"
        case .ncaafb: "College Football"
        case .ncaamb: "College Basketball"
        case .mls: "MLS"
        }
    }

    var shortName: String {
        switch self {
        case .nba: "NBA"
        case .nfl: "NFL"
        case .nhl: "NHL"
        case .mlb: "MLB"
        case .ncaafb: "CFB"
        case .ncaamb: "CBB"
        case .mls: "MLS"
        }
    }

    var icon: String {
        switch self {
        case .nba: "basketball.fill"
        case .nfl: "football.fill"
        case .nhl: "hockey.puck.fill"
        case .mlb: "baseball.fill"
        case .ncaafb: "football.fill"
        case .ncaamb: "basketball.fill"
        case .mls: "soccerball"
        }
    }

    var color: Color {
        switch self {
        case .nba: .orange
        case .nfl: .green
        case .nhl: .blue
        case .mlb: .red
        case .ncaafb: .mint
        case .ncaamb: .purple
        case .mls: .teal
        }
    }

    var espnSport: String {
        switch self {
        case .nba: "nba"
        case .nfl: "nfl"
        case .nhl: "nhl"
        case .mlb: "mlb"
        case .ncaafb: "ncaa"
        case .ncaamb: "ncaa"
        case .mls: "soccer"
        }
    }

    /// Sport path segment used for ESPN player headshot URLs.
    var espnHeadshotSport: String {
        switch self {
        case .nba: "nba"
        case .nfl: "nfl"
        case .nhl: "nhl"
        case .mlb: "mlb"
        case .ncaafb: "college-football"
        case .ncaamb: "mens-college-basketball"
        case .mls: "soccer"
        }
    }

    /// Builds the ESPN headshot URL for a player in this league.
    static func playerHeadshotURL(espnId: String, league: League, size: Int = 96) -> URL? {
        let sport = league.espnHeadshotSport
        return URL(string: "https://a.espncdn.com/combiner/i?img=/i/headshots/\(sport)/players/full/\(espnId).png&w=\(size)&h=\(size)")
    }

    /// Builds the ESPN team logo URL for a team in this league by ESPN team ID.
    static func teamLogoURL(espnId: String, league: League) -> URL? {
        URL(string: "https://a.espncdn.com/i/teamlogos/\(league.espnSport)/500/\(espnId).png")
    }

    /// ESPN league logo URL.
    var leagueLogoURL: URL? {
        let slug: String
        switch self {
        case .nba: slug = "nba"
        case .nfl: slug = "nfl"
        case .nhl: slug = "nhl"
        case .mlb: slug = "mlb"
        case .ncaafb: slug = "college-football"
        case .ncaamb: slug = "mens-college-basketball"
        case .mls: slug = "mls"
        }
        return URL(string: "https://a.espncdn.com/combiner/i?img=/i/leagues/500/\(slug).png")
    }

    // Only triggers the backend can actually match are exposed here. See
    // TRIGGER_MAP / parsePlay in backend/lib/alerts.ts. Triggers like
    // `assist`, `hatTrick`, `shutout`, `gameWinner`, `penaltyKick`, `error`
    // remain in the TriggerType enum so existing DB rows still render in
    // AlertDetailView, but we stop offering them in AddAlertView.
    var triggers: [TriggerType] {
        switch self {
        case .nba: [.pointsScored, .turnover, .technicalFoul, .ejection, .threePointer, .block, .steal, .dunk, .teamWin, .teamLoss]
        case .nfl: [.touchdown, .interception, .fumble, .sack, .fieldGoal, .reception, .rush, .teamWin, .teamLoss]
        case .nhl: [.goalScored, .goalAllowed, .assist, .penalty, .hatTrick, .shutout, .shotOnGoal, .hit, .blockedShot, .takeaway, .giveaway, .teamWin, .teamLoss]
        case .mlb: [.homeRunAllowed, .homeRunHit, .strikeoutPitched, .strikeoutBatting, .stolenBase, .error, .walk, .double, .single, .teamWin, .teamLoss]
        case .ncaafb: [.touchdown, .fieldGoal, .teamWin, .teamLoss]
        case .ncaamb: [.pointsScored, .teamWin, .teamLoss]
        case .mls: [.goal, .redCard, .teamWin, .teamLoss]
        }
    }
}

enum TriggerType: String, Codable, CaseIterable, Identifiable {
    case pointsScored = "points_scored"
    case turnover
    case technicalFoul = "technical_foul"
    case ejection
    case gameWinner = "game_winner"
    case teamWin = "team_win"
    case teamLoss = "team_loss"
    case touchdown
    case interception
    case fumble
    case sack
    case fieldGoal = "field_goal"
    case goal
    case assist
    case penalty
    case hatTrick = "hat_trick"
    case shutout
    case homeRun = "home_run"
    case strikeout
    case stolenBase = "stolen_base"
    case error
    case redCard = "red_card"
    case penaltyKick = "penalty_kick"
    case threePointer = "three_pointer"
    case block
    case dunk
    case steal
    case reception
    case rush
    case shotOnGoal = "shot_on_goal"
    case hit
    case blockedShot = "blocked_shot"
    case takeaway
    case giveaway
    case walk
    case double
    case single
    case homeRunAllowed = "home_run_allowed"
    case homeRunHit = "home_run_hit"
    case strikeoutPitched = "strikeout_pitched"
    case strikeoutBatting = "strikeout_batting"
    case goalScored = "goal_scored"
    case goalAllowed = "goal_allowed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pointsScored: "Points Scored"
        case .turnover: "Turnover"
        case .technicalFoul: "Technical Foul"
        case .ejection: "Ejection"
        case .gameWinner: "Game Winner"
        case .teamWin: "Team Win"
        case .teamLoss: "Team Loss"
        case .touchdown: "Touchdown"
        case .interception: "Interception"
        case .fumble: "Fumble"
        case .sack: "Sack"
        case .fieldGoal: "Field Goal"
        case .goal: "Goal"
        case .assist: "Assist"
        case .penalty: "Penalty"
        case .hatTrick: "Hat Trick"
        case .shutout: "Shutout"
        case .homeRun: "Home Run"
        case .strikeout: "Strikeout"
        case .stolenBase: "Stolen Base"
        case .error: "Error"
        case .redCard: "Red Card"
        case .penaltyKick: "Penalty Kick"
        case .threePointer: "Three Pointer"
        case .block: "Block"
        case .dunk: "Dunk"
        case .steal: "Steal"
        case .reception: "Reception"
        case .rush: "Rush"
        case .shotOnGoal: "Shot on Goal"
        case .hit: "Hit"
        case .blockedShot: "Blocked Shot"
        case .takeaway: "Takeaway"
        case .giveaway: "Giveaway"
        case .walk: "Walk"
        case .double: "Double"
        case .single: "Single"
        case .homeRunAllowed: "HR Allowed"
        case .homeRunHit: "Home Runs"
        case .strikeoutPitched: "Ks Thrown"
        case .strikeoutBatting: "Ks at Bat"
        case .goalScored: "Goals"
        case .goalAllowed: "Goals Allowed"
        }
    }

    var shortLabel: String {
        switch self {
        case .pointsScored: "PTS"
        case .turnover: "TOs"
        case .technicalFoul: "TECH"
        case .ejection: "EJECT"
        case .gameWinner: "GW"
        case .teamWin: "WIN"
        case .teamLoss: "LOSS"
        case .touchdown: "TDs"
        case .interception: "INTs"
        case .fumble: "FUM"
        case .sack: "SACK"
        case .fieldGoal: "FG"
        case .goal: "GOAL"
        case .assist: "AST"
        case .penalty: "PEN"
        case .hatTrick: "HAT"
        case .shutout: "SO"
        case .homeRun: "HRs"
        case .strikeout: "Ks"
        case .stolenBase: "SB"
        case .error: "ERR"
        case .redCard: "RED"
        case .penaltyKick: "PK"
        case .threePointer: "3PT"
        case .block: "BLK"
        case .dunk: "DUNK"
        case .steal: "STL"
        case .reception: "REC"
        case .rush: "RUSH"
        case .shotOnGoal: "SOG"
        case .hit: "HIT"
        case .blockedShot: "BS"
        case .takeaway: "TA"
        case .giveaway: "GA"
        case .walk: "BB"
        case .double: "2B"
        case .single: "1B"
        case .homeRunAllowed: "HRA"
        case .homeRunHit: "HRs"
        case .strikeoutPitched: "Ks"
        case .strikeoutBatting: "KBats"
        case .goalScored: "GOAL"
        case .goalAllowed: "GA"
        }
    }

    var triggerDescription: String {
        switch self {
        case .pointsScored: "Puts the ball through the hoop"
        case .turnover: "Ball lost to the other team"
        case .technicalFoul: "Unsportsmanlike conduct call"
        case .ejection: "Tossed from the game"
        case .gameWinner: "Hits the clutch shot to win it"
        case .teamWin: "Team wins the game"
        case .teamLoss: "Team loses the game"
        case .touchdown: "Scores a TD"
        case .interception: "Pass picked off by the defense"
        case .fumble: "Loses the ball on the ground"
        case .sack: "Quarterback taken down behind the line"
        case .fieldGoal: "Kicks it through the uprights"
        case .goal: "Puts it in the net"
        case .assist: "Sets up a teammate to score"
        case .penalty: "Sent to the box for an infraction"
        case .hatTrick: "Scores three goals in a game"
        case .shutout: "Goalie allows zero goals"
        case .homeRun: "Hits one out of the park"
        case .strikeout: "Batter goes down swinging"
        case .stolenBase: "Swipes a base on the basepath"
        case .error: "Fielding mistake lets a runner advance"
        case .redCard: "Ejected from the match"
        case .penaltyKick: "Awarded a shot from the spot"
        case .threePointer: "Drains one from beyond the arc"
        case .block: "Swats the shot away"
        case .dunk: "Throws it down with authority"
        case .steal: "Rips the ball away"
        case .reception: "Catches a pass"
        case .rush: "Carries the ball"
        case .shotOnGoal: "Fires a shot on net"
        case .hit: "Delivers a body check"
        case .blockedShot: "Blocks a shot on goal"
        case .takeaway: "Takes the puck away"
        case .giveaway: "Turns the puck over"
        case .walk: "Draws a base on balls"
        case .double: "Lines one into the gap"
        case .single: "Knocks a base hit"
        case .homeRunAllowed: "When they give up a home run"
        case .homeRunHit: "When they hit one out"
        case .strikeoutPitched: "When they strike someone out"
        case .strikeoutBatting: "When they strike out"
        case .goalScored: "When they put it in the net"
        case .goalAllowed: "When they give one up"
        }
    }

    /// League-aware role grouping for the trigger picker. Returns the section
    /// heading a trigger belongs under when grouping is enabled for a player
    /// in that league, or `nil` if the league doesn't group triggers.
    func roleGroup(for league: League) -> RoleGroup? {
        switch league {
        case .mlb:
            switch self {
            case .strikeoutPitched, .homeRunAllowed, .walk: return .pitching
            case .homeRunHit, .strikeoutBatting, .stolenBase, .double, .single, .error: return .batting
            case .teamWin, .teamLoss: return .team
            case .homeRun, .strikeout: return .batting // legacy rows → batter side
            default: return nil
            }
        case .nhl:
            switch self {
            case .goalAllowed, .shutout: return .goalie
            case .goalScored, .assist, .penalty, .hatTrick, .shotOnGoal, .hit, .blockedShot, .takeaway, .giveaway: return .skating
            case .teamWin, .teamLoss: return .team
            case .goal: return .skating // legacy rows → scorer side
            default: return nil
            }
        default:
            return nil
        }
    }
}

/// Section header for the grouped trigger picker. Sort order determines
/// the order of sections in the UI (role-specific first, `.team` last).
enum RoleGroup: String, Comparable {
    case pitching = "PITCHING"
    case batting = "BATTING"
    case skating = "SKATING"
    case goalie = "GOALIE"
    case team = "TEAM"

    static func < (lhs: RoleGroup, rhs: RoleGroup) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var sortOrder: Int {
        switch self {
        case .pitching: 0
        case .batting: 1
        case .skating: 0
        case .goalie: 1
        case .team: 99
        }
    }
}

enum SubscriptionType: String, Codable {
    case playerStat = "player_stat"
    case teamEvent = "team_event"
}

enum DeliveryMethod: String, Codable, CaseIterable, Identifiable {
    case push, sms, tweet

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push: "Push Notification"
        case .sms: "SMS Text"
        case .tweet: "Tag on X"
        }
    }

    var icon: String {
        switch self {
        case .push: "bell.fill"
        case .sms: "message.fill"
        case .tweet: "bird"
        }
    }

    var requiresContact: Bool {
        self == .sms || self == .tweet
    }
}

struct Subscription: Codable, Identifiable, Hashable {
    static func == (lhs: Subscription, rhs: Subscription) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    let id: String
    let userId: String
    let type: SubscriptionType
    let league: League
    let entityId: String
    let entityName: String
    let teamId: String?
    let photoUrl: String?
    let trigger: TriggerType
    let deliveryMethod: DeliveryMethod
    var active: Bool
    let createdAt: Date
    /// MLB-only position code (e.g. "P", "SP", "RP", "C", "1B", "OF") populated
    /// by the backend when the subscription is created for an MLB player. Used
    /// by the backend to match role-aware triggers. Nullable for non-MLB subs
    /// or when position lookup fails. Purely informational on the client.
    let position: String?
}
