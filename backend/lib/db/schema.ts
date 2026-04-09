import {
  pgTable,
  text,
  timestamp,
  boolean,
  pgEnum,
  uuid,
} from "drizzle-orm/pg-core";

// Enums
export const planEnum = pgEnum("plan", ["free", "premium"]);
export const deliveryMethodEnum = pgEnum("delivery_method", ["push", "sms", "both"]);
export const subscriptionTypeEnum = pgEnum("subscription_type", ["player_stat", "team_event"]);
export const leagueEnum = pgEnum("league", ["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"]);
export const gameStatusEnum = pgEnum("game_status", ["pre", "in", "post"]);

// Users
export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: text("email").notNull(),
  phone: text("phone"),
  apnsToken: text("apns_token"),
  plan: planEnum("plan").notNull().default("free"),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// Subscriptions
export const subscriptions = pgTable("subscriptions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id),
  type: subscriptionTypeEnum("type").notNull(),
  league: leagueEnum("league").notNull(),
  entityId: text("entity_id").notNull(),
  entityName: text("entity_name").notNull(),
  trigger: text("trigger").notNull(),
  deliveryMethod: deliveryMethodEnum("delivery_method").notNull().default("push"),
  active: boolean("active").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// Alerts
export const alerts = pgTable("alerts", {
  id: uuid("id").primaryKey().defaultRandom(),
  subscriptionId: uuid("subscription_id").notNull().references(() => subscriptions.id),
  userId: uuid("user_id").notNull().references(() => users.id),
  message: text("message").notNull(),
  sentAt: timestamp("sent_at").notNull().defaultNow(),
  deliveryMethod: text("delivery_method").notNull(),
  gameId: text("game_id").notNull(),
  eventDescription: text("event_description").notNull(),
});

// Games (tracks polling state)
export const games = pgTable("games", {
  id: text("id").primaryKey(), // ESPN game ID
  league: leagueEnum("league").notNull(),
  homeTeam: text("home_team").notNull(),
  awayTeam: text("away_team").notNull(),
  status: gameStatusEnum("status").notNull().default("pre"),
  lastPolledAt: timestamp("last_polled_at"),
  lastPlayId: text("last_play_id"),
});
