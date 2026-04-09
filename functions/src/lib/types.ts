/** Firestore document types matching SKILL.md schema */

export type League = "nba" | "nfl" | "nhl" | "mlb" | "ncaafb" | "ncaamb" | "mls";
export type Plan = "free" | "premium";
export type DeliveryMethod = "push" | "sms" | "both";
export type SubscriptionType = "player_stat" | "team_event";
export type GameStatus = "pre" | "in" | "post";

// Trigger types per league
export type NBATrigger = "points_scored" | "turnover" | "technical_foul" | "ejection" | "game_winner" | "team_win" | "team_loss";
export type NFLTrigger = "touchdown" | "interception" | "fumble" | "sack" | "field_goal" | "team_win" | "team_loss";
export type NHLTrigger = "goal" | "assist" | "penalty" | "hat_trick" | "shutout" | "team_win" | "team_loss";
export type MLBTrigger = "home_run" | "strikeout" | "stolen_base" | "error" | "team_win" | "team_loss";
export type CollegeTrigger = "touchdown" | "field_goal" | "points_scored" | "team_win" | "team_loss";
export type SoccerTrigger = "goal" | "red_card" | "penalty_kick" | "team_win" | "team_loss";

export type Trigger = NBATrigger | NFLTrigger | NHLTrigger | MLBTrigger | CollegeTrigger | SoccerTrigger;

/** /users/{userId} */
export interface UserDoc {
  email: string;
  phone: string | null;
  fcmToken: string;
  plan: Plan;
  createdAt: FirebaseFirestore.Timestamp;
}

/** /subscriptions/{subscriptionId} */
export interface SubscriptionDoc {
  userId: string;
  type: SubscriptionType;
  league: League;
  entityId: string;
  entityName: string;
  trigger: Trigger;
  deliveryMethod: DeliveryMethod;
  active: boolean;
  createdAt: FirebaseFirestore.Timestamp;
}

/** /alerts/{alertId} */
export interface AlertDoc {
  subscriptionId: string;
  userId: string;
  message: string;
  sentAt: FirebaseFirestore.Timestamp;
  deliveryMethod: "push" | "sms";
  gameId: string;
  eventDescription: string;
}

/** /games/{gameId} */
export interface GameDoc {
  league: League;
  homeTeam: string;
  awayTeam: string;
  status: GameStatus;
  lastPolledAt: FirebaseFirestore.Timestamp;
  lastPlayId: string;
}

/** ESPN API response types */
export interface ESPNScoreboardResponse {
  events: ESPNEvent[];
}

export interface ESPNEvent {
  id: string;
  name: string;
  status: {
    type: {
      state: "pre" | "in" | "post";
    };
    displayClock: string;
    period: number;
  };
  competitions: Array<{
    competitors: Array<{
      team: { abbreviation: string; displayName: string; id: string };
      score: string;
      homeAway: "home" | "away";
    }>;
  }>;
}

export interface ESPNPlay {
  id: string;
  text: string;
  type: { id: string; text: string };
  participants?: Array<{
    athlete: { id: string; displayName: string };
  }>;
  team?: { id: string };
  scoreValue?: number;
}
