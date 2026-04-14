import {
  pgTable,
  text,
  timestamp,
  boolean,
  pgEnum,
  uuid,
  integer,
  index,
  uniqueIndex,
} from "drizzle-orm/pg-core";
import { sql } from "drizzle-orm";

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
  // Stable Apple user ID (the `sub` claim from a verified Sign in with Apple
  // identity token). Nullable so that legacy test users created via
  // `/api/register` (before SIWA was wired up) remain functional. New users
  // created through `/api/auth/apple` always populate this.
  appleUserId: text("apple_user_id").unique(),
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
  // For MLB player subscriptions only: the player's position abbreviation
  // ("P", "SP", "RP", "C", "1B", "OF", etc.). Populated server-side at
  // creation time via the ESPN athlete endpoint. Null for non-MLB and team
  // subscriptions. Used by role-aware MLB trigger matching in alerts.ts to
  // pick whether a play's batter-side or pitcher-side role applies.
  position: text("position"),
  // For MLB player subscriptions only: the MLB Stats API player ID
  // (statsapi.mlb.com). Our primary `entityId` is the ESPN ID (used for
  // headshots + search), but the MLB Stats API play-by-play feed uses its
  // own numeric IDs for batter/pitcher/runner, so we resolve+cache this
  // once at subscription creation time.
  externalPlayerId: text("external_player_id"),
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
    // ESPN's stable play identifier. Null for events that aren't per-play
    // (e.g. team_win on game-end). The unique partial index below enforces
    // at-most-one alert per (subscription, game, play) when set.
    playId: text("play_id"),
  },
  (t) => [
    index("alerts_dedupe_idx").on(
      t.subscriptionId,
      t.gameId,
      t.eventDescription,
      t.sentAt
    ),
    uniqueIndex("alerts_play_unique_idx")
      .on(t.subscriptionId, t.gameId, t.playId)
      .where(sql`${t.playId} IS NOT NULL`),
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
