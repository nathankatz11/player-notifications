import Foundation

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

struct Subscription: Codable, Identifiable {
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
