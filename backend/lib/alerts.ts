/**
 * Alert matching engine.
 * Matches ESPN plays to user subscriptions and dispatches notifications.
 */

import { eq, and, gte, inArray } from "drizzle-orm";
import { db } from "./db";
import { subscriptions, alerts } from "./db/schema";
import { sendPushToUser } from "./apns";
import { sendSMSToUser } from "./twilio";
import { log } from "./logger";
import type { ESPNPlay, ESPNEvent, League } from "./espn";

type Trigger = string;

export interface ParsedPlay {
  /**
   * Every id this play is "about" — typically [playerId, teamId] — so a
   * single play fires both player-specific and team-level subscriptions
   * that reference either. `entityIds[0]` is the canonical one (player if
   * present, else team) used for logging.
   */
  entityIds: string[];
  /** Deprecated alias; first of `entityIds`. Kept for readability in a few call sites. */
  entityId: string;
  /**
   * Triggers that should fire for this play. A single play can match several
   * — e.g. a made three-pointer matches both "three_pointer" and
   * "points_scored". `triggers[0]` is the canonical label used when
   * formatting the alert message.
   */
  triggers: Trigger[];
  description: string;
}

/**
 * Minimal shape of a subscription row for matching. Using a structural type
 * here (instead of the full Drizzle row type) keeps these helpers trivially
 * testable without pulling in db/schema.
 */
export interface SubscriptionLike {
  entityId: string;
  trigger: string;
  active: boolean;
}

/**
 * Minimal shape of an alert row for dedupe. Dedupe key is
 * (subscriptionId, gameId, playId) — ESPN's play id is stable per play, so
 * this is tolerant to ESPN rewriting a play's text between polls and also
 * distinguishes two plays in the same game with identical text.
 */
export interface AlertLike {
  subscriptionId: string;
  gameId: string;
  playId: string;
}

/** Sport emoji per league */
const LEAGUE_EMOJI: Record<League, string> = {
  nba: "🏀",
  nfl: "🏈",
  nhl: "🏒",
  mlb: "⚾",
  ncaafb: "🏈",
  ncaamb: "🏀",
  mls: "⚽",
};

/** Human-readable uppercase labels for each trigger */
const TRIGGER_LABEL: Record<string, string> = {
  turnover: "TURNOVER",
  touchdown: "TOUCHDOWN",
  field_goal: "FIELD GOAL",
  goal: "GOAL",
  home_run: "HOME RUN",
  strikeout: "STRIKEOUT",
  stolen_base: "STOLEN BASE",
  interception: "INTERCEPTION",
  fumble: "FUMBLE",
  sack: "SACK",
  penalty: "PENALTY",
  ejection: "EJECTION",
  technical_foul: "TECHNICAL FOUL",
  red_card: "RED CARD",
  three_pointer: "THREE",
  points_scored: "SCORE",
  block: "BLOCK",
  dunk: "DUNK",
  steal: "STEAL",
  reception: "RECEPTION",
  rush: "RUSH",
  shot_on_goal: "SHOT",
  hit: "HIT",
  blocked_shot: "BLOCKED SHOT",
  takeaway: "TAKEAWAY",
  giveaway: "GIVEAWAY",
  walk: "WALK",
  double: "DOUBLE",
  single: "SINGLE",
};

/**
 * Build a punchy alert string.
 * Format: {emoji} {TRIGGER} — {playText}. {scoreline} | {clock}
 */
export function formatAlertMessage(
  league: League,
  trigger: string,
  playText: string,
  event?: ESPNEvent
): string {
  const emoji = LEAGUE_EMOJI[league] ?? "🏅";
  const label = TRIGGER_LABEL[trigger] ?? trigger.replace(/_/g, " ").toUpperCase();

  let suffix = "";
  if (event) {
    const comp = event.competitions?.[0];
    if (comp) {
      const home = comp.competitors.find((c) => c.homeAway === "home");
      const away = comp.competitors.find((c) => c.homeAway === "away");
      if (home && away) {
        const scoreline = `${away.team.abbreviation} ${away.score}, ${home.team.abbreviation} ${home.score}`;
        const state = event.status?.type?.state;
        if (state === "post") {
          suffix = ` ${scoreline} | Final`;
        } else {
          const clock = event.status?.displayClock ?? "";
          const period = event.status?.period ?? 0;
          const periodLabel = getPeriodLabel(league, period);
          suffix = ` ${scoreline} | ${periodLabel} ${clock}`;
        }
      }
    }
  }

  return `${emoji} ${label} — ${playText}.${suffix}`;
}

function getPeriodLabel(league: League, period: number): string {
  if (league === "nhl" || league === "mls") {
    const ordinal = period === 1 ? "1st" : period === 2 ? "2nd" : period === 3 ? "3rd" : `${period}th`;
    return `${ordinal} Period`;
  }
  if (league === "mlb") {
    return period % 2 === 1 ? `Top ${Math.ceil(period / 2)}` : `Bot ${Math.ceil(period / 2)}`;
  }
  // Basketball / Football use Q1-Q4
  return `Q${period}`;
}

/**
 * Match a play against active subscriptions and dispatch alerts.
 */
export async function matchAndAlert(
  play: ESPNPlay,
  gameId: string,
  league: League,
  event?: ESPNEvent
): Promise<number> {
  const parsed = parsePlay(play, league, event);
  if (!parsed) return 0;

  const { entityIds, triggers, description } = parsed;

  // Find matching subscriptions — a play can carry multiple triggers AND
  // multiple candidate ids (player + team), so a single MLB at-bat fires
  // both "Pete Alonso home_run" (player sub) and "Mets home_run" (team sub).
  const matchingSubs = await db
    .select()
    .from(subscriptions)
    .where(
      and(
        inArray(subscriptions.entityId, entityIds),
        inArray(subscriptions.trigger, triggers),
        eq(subscriptions.active, true)
      )
    );

  if (matchingSubs.length === 0) return 0;

  // Batched dedupe by ESPN play id: fetch all existing (subscriptionId,
  // gameId, playId) rows from the last 24h in ONE query. play.id is stable
  // per play, so ESPN text rewrites don't cause duplicates and two distinct
  // plays with identical text don't collide.
  const matchingSubIds = matchingSubs.map((s) => s.id);
  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const existing = matchingSubIds.length > 0 && play.id
    ? await db
        .select({
          subscriptionId: alerts.subscriptionId,
          gameId: alerts.gameId,
          playId: alerts.playId,
        })
        .from(alerts)
        .where(
          and(
            inArray(alerts.subscriptionId, matchingSubIds),
            eq(alerts.gameId, gameId),
            eq(alerts.playId, play.id),
            gte(alerts.sentAt, twentyFourHoursAgo)
          )
        )
    : [];

  let dispatched = 0;

  for (const sub of matchingSubs) {
    const candidate: AlertLike = {
      subscriptionId: sub.id,
      gameId,
      playId: play.id ?? "",
    };
    if (play.id && isDuplicateAlert(candidate, existing.map((e) => ({
      subscriptionId: e.subscriptionId,
      gameId: e.gameId,
      playId: e.playId ?? "",
    })))) {
      log.info("alerts.dedupe_skip", {
        subscriptionId: sub.id,
        gameId,
        playId: play.id,
      });
      continue;
    }

    // Insert the alert row first so we have an `alertId` to embed in the push
    // payload (enables iOS deep-linking from the notification tap). The DB
    // has a partial unique index on (subscription_id, game_id, play_id) that
    // hard-fails duplicate inserts as a second line of defense against the
    // race between the SELECT above and this INSERT under concurrent cron
    // retries.
    let alertRow;
    try {
      [alertRow] = await db
        .insert(alerts)
        .values({
          subscriptionId: sub.id,
          userId: sub.userId,
          message: description,
          deliveryMethod: sub.deliveryMethod ?? "push",
          gameId,
          eventDescription: play.text,
          playId: play.id ?? null,
        })
        .returning();
    } catch (err) {
      // Unique-constraint violation on (sub, game, play) — another invocation
      // won the race. Skip silently; the other one already sent the push.
      log.info("alerts.dedupe_race", {
        subscriptionId: sub.id,
        gameId,
        playId: play.id,
        error: String(err),
      });
      continue;
    }

    // Send push notification
    if (sub.deliveryMethod === "push" || sub.deliveryMethod === "both") {
      await sendPushToUser(sub.userId, description, {
        subscriptionId: sub.id,
        alertId: alertRow?.id,
      });
    }

    // Send SMS (premium only — twilio.ts checks plan)
    if (sub.deliveryMethod === "sms" || sub.deliveryMethod === "both") {
      await sendSMSToUser(sub.userId, description);
    }

    dispatched++;
  }

  return dispatched;
}

/**
 * Dispatch team_win / team_loss alerts for a just-finished game.
 * Dedupes via the alerts table so repeat polls after the final don't re-fire.
 */
export async function dispatchTeamResult(
  event: ESPNEvent,
  league: League
): Promise<number> {
  const comp = event.competitions?.[0];
  if (!comp || event.status?.type?.state !== "post") return 0;

  const teamIds = comp.competitors.map((c) => c.team.id);
  if (teamIds.length === 0) return 0;

  const candidates = await db
    .select()
    .from(subscriptions)
    .where(
      and(
        inArray(subscriptions.entityId, teamIds),
        inArray(subscriptions.trigger, ["team_win", "team_loss"]),
        eq(subscriptions.active, true)
      )
    );

  if (candidates.length === 0) return 0;

  const home = comp.competitors.find((c) => c.homeAway === "home");
  const away = comp.competitors.find((c) => c.homeAway === "away");
  const scoreline =
    home && away
      ? `${away.team.abbreviation} ${away.score}, ${home.team.abbreviation} ${home.score}`
      : "";
  const emoji = LEAGUE_EMOJI[league] ?? "🏅";

  // Batched dedupe: fetch all (subscriptionId, gameId) rows for candidate subs
  // in ONE query. team-result dedupe ignores eventDescription (there's only
  // ever one team_result per sub per game), so we key on (sub, game) only.
  const candidateIds = candidates.map((s) => s.id);
  const existingTeamAlerts = candidateIds.length > 0
    ? await db
        .select({ subscriptionId: alerts.subscriptionId, gameId: alerts.gameId })
        .from(alerts)
        .where(
          and(
            inArray(alerts.subscriptionId, candidateIds),
            eq(alerts.gameId, event.id)
          )
        )
    : [];
  const firedSubIds = new Set(existingTeamAlerts.map((a) => a.subscriptionId));

  let dispatched = 0;

  for (const sub of candidates) {
    if (!matchesTeamResult(event, sub)) continue;
    if (firedSubIds.has(sub.id)) continue;

    const team = comp.competitors.find((c) => c.team.id === sub.entityId);
    const teamName = team?.team.displayName ?? "Team";
    const label = sub.trigger === "team_win" ? "WIN" : "LOSS";
    const verb = sub.trigger === "team_win" ? "won" : "lost";
    const suffix = scoreline ? ` ${scoreline} | Final` : " | Final";
    const message = `${emoji} ${label} — ${teamName} ${verb}.${suffix}`;

    const [alertRow] = await db
      .insert(alerts)
      .values({
        subscriptionId: sub.id,
        userId: sub.userId,
        message,
        deliveryMethod: sub.deliveryMethod ?? "push",
        gameId: event.id,
        eventDescription: `team_result:${sub.trigger}`,
      })
      .returning();

    if (sub.deliveryMethod === "push" || sub.deliveryMethod === "both") {
      await sendPushToUser(sub.userId, message, {
        subscriptionId: sub.id,
        alertId: alertRow?.id,
      });
    }
    if (sub.deliveryMethod === "sms" || sub.deliveryMethod === "both") {
      await sendSMSToUser(sub.userId, message);
    }

    dispatched++;
  }

  return dispatched;
}

/** Map ESPN play types to our trigger system */
const TRIGGER_MAP: Record<string, Trigger> = {
  "turnover": "turnover",
  "lost ball turnover": "turnover",
  "bad pass turnover": "turnover",
  "touchdown": "touchdown",
  "rushing touchdown": "touchdown",
  "passing touchdown": "touchdown",
  "field goal": "field_goal",
  "goal": "goal",
  "home run": "home_run",
  "strikeout": "strikeout",
  "stolen base": "stolen_base",
  "interception": "interception",
  "fumble": "fumble",
  "sack": "sack",
  "penalty": "penalty",
  "ejection": "ejection",
  "technical foul": "technical_foul",
  "red card": "red_card",
  // NBA
  "three point": "three_pointer",
  "block": "block",
  "dunk": "dunk",
  "steal": "steal",
  // NFL
  "pass reception": "reception",
  "rush": "rush",
  // NHL
  "shot": "shot_on_goal",
  "hit": "hit",
  "blocked": "blocked_shot",
  "takeaway": "takeaway",
  "giveaway": "giveaway",
  // MLB
  "walk": "walk",
  "double": "double",
  "single": "single",
};

/**
 * Pure predicate: does this parsed play match this subscription?
 *
 * A subscription matches when its entityId equals the play's entityId (the
 * player or team involved), the subscription's trigger equals the play's
 * trigger, and the subscription is active.
 */
export function matchesSubscription(
  parsed: ParsedPlay,
  sub: SubscriptionLike
): boolean {
  if (!sub.active) return false;
  if (!parsed.entityIds.includes(sub.entityId)) return false;
  if (!parsed.triggers.includes(sub.trigger)) return false;
  return true;
}

/**
 * Pure predicate: does this game-end event match a team_win / team_loss
 * subscription? Only fires once the game state is "post" (final).
 *
 * This helper is ready to be wired into `matchAndAlert` when team-event
 * matching is added to the polling cron. It lives here so the behavior is
 * unit-tested up-front and the match logic is not scattered across routes.
 */
export function matchesTeamResult(
  event: ESPNEvent,
  sub: SubscriptionLike
): boolean {
  if (!sub.active) return false;
  if (sub.trigger !== "team_win" && sub.trigger !== "team_loss") return false;

  // Only fire on final
  if (event.status?.type?.state !== "post") return false;

  const comp = event.competitions?.[0];
  if (!comp) return false;

  const subbed = comp.competitors.find((c) => c.team.id === sub.entityId);
  const other = comp.competitors.find((c) => c.team.id !== sub.entityId);
  if (!subbed || !other) return false;

  const subbedScore = Number(subbed.score);
  const otherScore = Number(other.score);
  if (Number.isNaN(subbedScore) || Number.isNaN(otherScore)) return false;

  if (sub.trigger === "team_win") return subbedScore > otherScore;
  return subbedScore < otherScore;
}

/**
 * Pure dedupe predicate: has an alert for this (subscription, game, play)
 * already been recorded? Callers pass in the existing alerts rows they've
 * fetched — the predicate itself does no I/O.
 */
export function isDuplicateAlert(
  candidate: AlertLike,
  existing: readonly AlertLike[]
): boolean {
  if (!candidate.playId) return false;
  return existing.some(
    (a) =>
      a.subscriptionId === candidate.subscriptionId &&
      a.gameId === candidate.gameId &&
      a.playId === candidate.playId
  );
}

const BASKETBALL_LEAGUES: League[] = ["nba", "ncaamb"];

export function parsePlay(play: ESPNPlay, league: League, event?: ESPNEvent): ParsedPlay | null {
  const playType = play.type?.text?.toLowerCase() ?? "";
  const text = play.text?.toLowerCase() ?? "";
  const playerName = play.participants?.[0]?.athlete?.displayName ?? "Unknown";
  const playerId = play.participants?.[0]?.athlete?.id ?? "";
  const teamId = play.team?.id ?? "";

  if (!playerId && !teamId) return null;

  const triggers: Trigger[] = [];

  // Primary trigger from the play-type map.
  const primary = TRIGGER_MAP[playType];
  if (primary) triggers.push(primary);

  // Basketball text-based triggers (NBA + NCAAMB). Word-boundary regex on
  // `block` and `steal` so we don't false-positive on "blockbuster",
  // "stealing time", etc.
  if (BASKETBALL_LEAGUES.includes(league)) {
    if (!triggers.includes("three_pointer") &&
        /\bthree\s+point\b/.test(text) && play.scoreValue === 3) {
      triggers.push("three_pointer");
    }
    if (!triggers.includes("block") && /\bblock\b/.test(text)) {
      triggers.push("block");
    }
    if (!triggers.includes("dunk") && /\bdunk\b/.test(playType)) {
      triggers.push("dunk");
    }
    if (!triggers.includes("steal") && /\bsteal\b/.test(text)) {
      triggers.push("steal");
    }
    // Any made basket (or free throw) also counts as points_scored.
    if (!triggers.includes("points_scored") &&
        typeof play.scoreValue === "number" && play.scoreValue >= 1) {
      triggers.push("points_scored");
    }
  }

  // MLB: ESPN reports plays with type="Play Result" and the actual outcome
  // only in `play.text` (e.g. "Muncy struck out swinging.",
  // "Pages homered to left..."). Detect outcomes from the text so the
  // per-play-type TRIGGER_MAP doesn't miss everything.
  if (league === "mlb") {
    if (!triggers.includes("home_run") && /\b(homered|home run|grand slam)\b/.test(text)) {
      triggers.push("home_run");
    }
    if (!triggers.includes("strikeout") && /\bstruck out\b/.test(text)) {
      triggers.push("strikeout");
    }
    if (!triggers.includes("walk") && /\bwalked\b/.test(text)) {
      triggers.push("walk");
    }
    if (!triggers.includes("single") && /\bsingled\b/.test(text)) {
      triggers.push("single");
    }
    if (!triggers.includes("double") && /\bdoubled\b/.test(text)) {
      triggers.push("double");
    }
    if (!triggers.includes("stolen_base") && /\bstole\s+(second|third|home)\b/.test(text)) {
      triggers.push("stolen_base");
    }
  }

  if (triggers.length === 0) return null;

  // Build a short play blurb: prefer player name + raw text, fall back to raw text
  const playText = playerName !== "Unknown"
    ? `${playerName} ${play.text}`
    : play.text;

  const entityIds = [playerId, teamId].filter((x): x is string => !!x);

  return {
    entityIds,
    entityId: entityIds[0],
    triggers,
    description: formatAlertMessage(league, triggers[0], playText, event),
  };
}
