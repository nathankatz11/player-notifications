import {
  pgTable,
  text,
  timestamp,
  boolean,
  pgEnum,
  uuid,
  integer,
  index,
} from "drizzle-orm/pg-core";

// Enums
export const planEnum = pgEnum("plan", ["free", "premium"]);
export const deliveryMethodEnum = pgEnum("delivery_method", ["push", "sms", "both", "tweet"]);
export const subscriptionTypeEnum = pgEnum("subscription_type", ["player_stat", "team_event"]);
export const leagueEnum = pgEnum("league", ["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"]);
export const gameStatusEnum = pgEnum("game_status", ["pre", "in", "post"]);

// Users
export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: text("email").notNull(),
  phone: text("phone"),
  xHandle: text("x_handle"),
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
  // For player subscriptions: ESPN id of the player's current team. Populated
  // server-side at creation time so the client can filter "my games today"
  // without fanning out per-player ESPN lookups.
  teamId: text("team_id"),
  // For player subscriptions: ESPN-resolved headshot URL captured once at
  // creation time. Avoids per-render URL guessing (ESPN's combiner path
  // 404s or returns a silhouette for many athletes).
  photoUrl: text("photo_url"),
  trigger: text("trigger").notNull(),
  deliveryMethod: deliveryMethodEnum("delivery_method").notNull().default("push"),
  active: boolean("active").notNull().default(true),
  createdAt: timestamp("created_at").notNull().defaultNow(),
});

// Alerts
export const alerts = pgTable(
  "alerts",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    subscriptionId: uuid("subscription_id").notNull().references(() => subscriptions.id),
    userId: uuid("user_id").notNull().references(() => users.id),
    message: text("message").notNull(),
    sentAt: timestamp("sent_at").notNull().defaultNow(),
    deliveryMethod: text("delivery_method").notNull(),
    gameId: text("game_id").notNull(),
    eventDescription: text("event_description").notNull(),
  },
  (t) => [
    index("alerts_dedupe_idx").on(
      t.subscriptionId,
      t.gameId,
      t.eventDescription,
      t.sentAt
    ),
  ]
);

// Rate limits (fixed-window counter keyed by caller identity + bucket name)
export const rateLimits = pgTable("rate_limits", {
  key: text("key").primaryKey(),
  windowStart: timestamp("window_start", { withTimezone: true }).notNull(),
  count: integer("count").notNull().default(0),
});

// Games (tracks polling state)
export const games = pgTable("games", {
  id: text("id").primaryKey(), // ESPN game ID
  league: leagueEnum("league").notNull(),
  status: gameStatusEnum("status").notNull().default("pre"),
  lastPolledAt: timestamp("last_polled_at"),
  lastPlayId: text("last_play_id"),
});
