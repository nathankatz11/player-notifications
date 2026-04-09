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

    var triggers: [TriggerType] {
        switch self {
        case .nba: [.pointsScored, .turnover, .technicalFoul, .ejection, .gameWinner, .teamWin, .teamLoss]
        case .nfl: [.touchdown, .interception, .fumble, .sack, .fieldGoal, .teamWin, .teamLoss]
        case .nhl: [.goal, .assist, .penalty, .hatTrick, .shutout, .teamWin, .teamLoss]
        case .mlb: [.homeRun, .strikeout, .stolenBase, .error, .teamWin, .teamLoss]
        case .ncaafb: [.touchdown, .fieldGoal, .teamWin, .teamLoss]
        case .ncaamb: [.pointsScored, .teamWin, .teamLoss]
        case .mls: [.goal, .redCard, .penaltyKick, .teamWin, .teamLoss]
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
        }
    }
}

enum SubscriptionType: String, Codable {
    case playerStat = "player_stat"
    case teamEvent = "team_event"
}

enum DeliveryMethod: String, Codable, CaseIterable, Identifiable {
    case push, sms, both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .push: "Push Notification"
        case .sms: "SMS"
        case .both: "Push + SMS"
        }
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
    let trigger: TriggerType
    let deliveryMethod: DeliveryMethod
    var active: Bool
    let createdAt: Date
}
