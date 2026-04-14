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
import type { MLBPlay } from "./mlb";
import type { NHLPlay } from "./nhl";

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
  // Role-aware MLB triggers — the label is identical to the legacy
  // non-role one because the emoji+description already communicate
  // "X hit a HR off Y".
  home_run_hit: "HOME RUN",
  home_run_allowed: "HR ALLOWED",
  strikeout_batting: "STRIKEOUT",
  strikeout_pitched: "STRIKEOUT",
  // Role-aware NHL triggers. Labels reuse the flat "GOAL" wording because
  // the description itself conveys scorer vs goalie context.
  goal_scored: "GOAL",
  goal_allowed: "GOAL ALLOWED",
  assist: "ASSIST",
};

/**
 * Role-aware MLB triggers and whether they apply to a batter or pitcher.
 * Legacy ambiguous triggers (home_run, strikeout, stolen_base, walk) are
 * treated as "batter-side" for backward compatibility — existing
 * subscriptions created before this change keep firing as they did.
 */
type MLBRole = "batter" | "pitcher" | "runner";

const MLB_TRIGGER_ROLE: Record<string, MLBRole> = {
  home_run_hit: "batter",
  home_run_allowed: "pitcher",
  strikeout_batting: "batter",
  strikeout_pitched: "pitcher",
  // Legacy batter-side defaults
  home_run: "batter",
  strikeout: "batter",
  walk: "batter",
  stolen_base: "runner",
  single: "batter",
  double: "batter",
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
 * Firehose dispatcher — sends one push per new play to every user whose
 * `firehose_until` is in the future. No subscription matching, no alert
 * dedupe (by design; this is a verification stream, not a user-facing
 * feature). Intentionally cheap: runs after the normal match loop.
 */
export async function dispatchFirehose(
  plays: readonly ESPNPlay[],
  gameId: string,
  league: League,
  event?: ESPNEvent
): Promise<number> {
  if (plays.length === 0) return 0;

  const now = new Date();
  const { users } = await import("./db/schema");
  const firehoseUsers = await db
    .select({ id: users.id, apnsToken: users.apnsToken })
    .from(users)
    .where(gte(users.firehoseUntil, now));

  const deliverable = firehoseUsers.filter((u) => u.apnsToken);
  if (deliverable.length === 0) return 0;

  let sent = 0;
  for (const play of plays) {
    const playerName =
      play.participants?.[0]?.athlete?.displayName ?? "";
    const text = playerName
      ? `${playerName} ${play.text}`
      : play.text ?? "";
    const emoji = LEAGUE_EMOJI[league] ?? "🏅";
    const message = formatAlertMessage(
      league,
      "play",
      `${emoji} ${text}`,
      event
    );
    for (const user of deliverable) {
      const ok = await sendPushToUser(user.id, message);
      if (ok) sent++;
    }
  }
  return sent;
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

  // Batched dedupe: fetch all existing team_result alerts for candidate subs
  // in ONE query. Dedupe key is (subscriptionId, gameId, playId="team_result")
  // — reuses the partial unique index on alerts(subscriptionId, gameId, playId)
  // so concurrent polls can't double-fire.
  const candidateIds = candidates.map((s) => s.id);
  const existingTeamAlerts = candidateIds.length > 0
    ? await db
        .select({ subscriptionId: alerts.subscriptionId })
        .from(alerts)
        .where(
          and(
            inArray(alerts.subscriptionId, candidateIds),
            eq(alerts.gameId, event.id),
            eq(alerts.playId, "team_result")
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

    let alertRow;
    try {
      [alertRow] = await db
        .insert(alerts)
        .values({
          subscriptionId: sub.id,
          userId: sub.userId,
          message,
          deliveryMethod: sub.deliveryMethod ?? "push",
          gameId: event.id,
          eventDescription: `team_result:${sub.trigger}`,
          playId: "team_result",
        })
        .returning();
    } catch (err) {
      // Unique-constraint race: another concurrent cron run inserted the
      // same (sub, game, playId="team_result") first. Skip silently.
      log.info("alerts.team_result_dedupe_race", {
        subId: sub.id,
        gameId: event.id,
        error: String(err),
      });
      continue;
    }

    if (sub.deliveryMethod === "push" || sub.deliveryMethod === "both") {
      await sendPushToUser(sub.userId, message, {
        subscriptionId: sub.id,
        alertId: alertRow?.id,
      });
    }
    if (sub.deliveryMethod === "sms" || sub.deliveryMethod === "both") {
      await sendSMSToUser(sub.userId, message);
    }

    log.info("alerts.team_result_sent", {
      subId: sub.id,
      gameId: event.id,
      trigger: sub.trigger,
    });
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

// ----------------------- MLB Stats API provider path ----------------------
//
// When the cron processes an MLB game we feed the statsapi.mlb.com
// play-by-play feed through this path instead of the ESPN text-based one
// above. The key difference: every MLB play carries *explicit* batter AND
// pitcher IDs, so we can produce one `ParsedPlay` per (role, player) pair
// and let role-aware triggers (home_run_allowed, strikeout_pitched) fire
// for the right side of the matchup.

/**
 * Internal shape of a parsed MLB play, with an extra `role` tag so the
 * alert matcher knows whether each entry is the batter's side, the
 * pitcher's side, or a runner's side. Exposed for tests.
 */
export interface ParsedMLBEntry extends ParsedPlay {
  role: MLBRole;
}

/**
 * Pure function: turn a normalized MLB play into zero, one, or more
 * parsed entries — one per (role, entity) pair. A single home run
 * produces two entries: the batter (with triggers `home_run_hit` +
 * legacy `home_run`) and the pitcher (with `home_run_allowed`).
 */
export function parseMLBPlay(play: MLBPlay): ParsedMLBEntry[] {
  const entries: ParsedMLBEntry[] = [];
  const event = play.eventType;
  if (!event) return entries;

  const desc = play.description || event.replace(/_/g, " ");

  // Home run → batter & pitcher entries
  if (event === "home_run") {
    if (play.batterId) {
      entries.push({
        role: "batter",
        entityId: play.batterId,
        entityIds: [play.batterId],
        triggers: ["home_run_hit", "home_run"],
        description: `⚾ HOME RUN — ${desc}`,
      });
    }
    if (play.pitcherId) {
      entries.push({
        role: "pitcher",
        entityId: play.pitcherId,
        entityIds: [play.pitcherId],
        triggers: ["home_run_allowed"],
        description: `⚾ HR ALLOWED — ${desc}`,
      });
    }
    return entries;
  }

  // Strikeout → batter (strikeout_batting + legacy strikeout) & pitcher (strikeout_pitched)
  if (event === "strikeout") {
    if (play.batterId) {
      entries.push({
        role: "batter",
        entityId: play.batterId,
        entityIds: [play.batterId],
        triggers: ["strikeout_batting", "strikeout"],
        description: `⚾ STRIKEOUT — ${desc}`,
      });
    }
    if (play.pitcherId) {
      entries.push({
        role: "pitcher",
        entityId: play.pitcherId,
        entityIds: [play.pitcherId],
        triggers: ["strikeout_pitched"],
        description: `⚾ STRIKEOUT — ${desc}`,
      });
    }
    return entries;
  }

  // Walk → batter-side only (legacy trigger)
  if (event === "walk") {
    if (play.batterId) {
      entries.push({
        role: "batter",
        entityId: play.batterId,
        entityIds: [play.batterId],
        triggers: ["walk"],
        description: `⚾ WALK — ${desc}`,
      });
    }
    return entries;
  }

  // Single / double
  if (event === "single" || event === "double") {
    if (play.batterId) {
      entries.push({
        role: "batter",
        entityId: play.batterId,
        entityIds: [play.batterId],
        triggers: [event],
        description: `⚾ ${event.toUpperCase()} — ${desc}`,
      });
    }
    return entries;
  }

  // Stolen base — runner-side
  if (event.startsWith("stolen_base")) {
    const who = play.runnerId ?? play.batterId;
    if (who) {
      entries.push({
        role: "runner",
        entityId: who,
        entityIds: [who],
        triggers: ["stolen_base"],
        description: `⚾ STOLEN BASE — ${desc}`,
      });
    }
    return entries;
  }

  return entries;
}

/**
 * Pure predicate: does an MLB `ParsedMLBEntry` match a subscription,
 * comparing the sub's `externalPlayerId` (MLB Stats API id) against the
 * entry's entityId? Returns false for non-MLB subs or subs missing an
 * `externalPlayerId`. Role consistency is implicit: if a pitcher-side
 * trigger (home_run_allowed) is in the entry's triggers, only entries
 * where `role === "pitcher"` were produced for that trigger.
 */
export function matchesMLBEntry(
  entry: ParsedMLBEntry,
  sub: { externalPlayerId: string | null; trigger: string; active: boolean; league: string }
): boolean {
  if (!sub.active) return false;
  if (sub.league !== "mlb") return false;
  if (!sub.externalPlayerId) return false;
  if (!entry.triggers.includes(sub.trigger)) return false;
  if (entry.entityId !== sub.externalPlayerId) return false;

  // Extra safety: ensure the trigger's expected role lines up with the
  // entry's role. Prevents weirdness if a caller hand-builds entries.
  const expectedRole = MLB_TRIGGER_ROLE[sub.trigger];
  if (expectedRole && expectedRole !== entry.role) return false;
  return true;
}

/**
 * Match an MLB play (from statsapi.mlb.com) against active MLB
 * subscriptions and dispatch alerts.
 *
 * Differs from `matchAndAlert` in that the match is against the MLB
 * Stats API player ID (stored as `subscriptions.externalPlayerId`) rather
 * than the ESPN id in `subscriptions.entityId`. ESPN id is still stored
 * and used by the iOS client for headshots.
 */
export async function matchAndAlertMLB(
  play: MLBPlay,
  gameId: string,
  event?: ESPNEvent
): Promise<number> {
  const entries = parseMLBPlay(play);
  if (entries.length === 0) return 0;

  const allMlbIds = Array.from(
    new Set(entries.map((e) => e.entityId).filter((x): x is string => !!x))
  );
  const allTriggers = Array.from(new Set(entries.flatMap((e) => e.triggers)));

  if (allMlbIds.length === 0 || allTriggers.length === 0) return 0;

  // Only MLB player subs with a resolved externalPlayerId can possibly
  // match. We widen the trigger filter to include legacy values so an
  // existing `trigger="home_run"` subscription still fires on a HR.
  const matchingSubs = await db
    .select()
    .from(subscriptions)
    .where(
      and(
        eq(subscriptions.league, "mlb"),
        inArray(subscriptions.externalPlayerId, allMlbIds),
        inArray(subscriptions.trigger, allTriggers),
        eq(subscriptions.active, true)
      )
    );

  if (matchingSubs.length === 0) return 0;

  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const matchingSubIds = matchingSubs.map((s) => s.id);
  const existing = matchingSubIds.length > 0 && play.playId
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
            eq(alerts.playId, play.playId),
            gte(alerts.sentAt, twentyFourHoursAgo)
          )
        )
    : [];

  let dispatched = 0;

  // Match each sub against the entry list and pick the first entry whose
  // (entityId, trigger, role) aligns. This way a pitcher-sub for
  // "home_run_allowed" matches the pitcher entry (not the batter entry).
  for (const sub of matchingSubs) {
    const entry = entries.find((e) =>
      matchesMLBEntry(e, {
        externalPlayerId: sub.externalPlayerId,
        trigger: sub.trigger,
        active: sub.active,
        league: sub.league,
      })
    );
    if (!entry) continue;

    const description = formatAlertMessage(
      "mlb",
      entry.triggers[0],
      entry.description.replace(/^⚾\s+[A-Z ]+—\s*/, ""),
      event
    );

    const candidate: AlertLike = {
      subscriptionId: sub.id,
      gameId,
      playId: play.playId ?? "",
    };
    if (play.playId && isDuplicateAlert(candidate, existing.map((e) => ({
      subscriptionId: e.subscriptionId,
      gameId: e.gameId,
      playId: e.playId ?? "",
    })))) {
      log.info("alerts.dedupe_skip", {
        subscriptionId: sub.id,
        gameId,
        playId: play.playId,
      });
      continue;
    }

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
          eventDescription: play.description || play.eventType,
          playId: play.playId ?? null,
        })
        .returning();
    } catch (err) {
      log.info("alerts.dedupe_race", {
        subscriptionId: sub.id,
        gameId,
        playId: play.playId,
        error: String(err),
      });
      continue;
    }

    if (sub.deliveryMethod === "push" || sub.deliveryMethod === "both") {
      await sendPushToUser(sub.userId, description, {
        subscriptionId: sub.id,
        alertId: alertRow?.id,
      });
    }
    if (sub.deliveryMethod === "sms" || sub.deliveryMethod === "both") {
      await sendSMSToUser(sub.userId, description);
    }
    dispatched++;
  }

  return dispatched;
}

// ----------------------- NHL API provider path ---------------------------
//
// NHL play-by-play (api-web.nhle.com) is role-specific: a goal carries a
// scorer, up-to-two assisters, AND the goalie-in-net whose line got beat.
// That's exactly what's needed to fire "goal_allowed" on a goalie sub
// without fighting text heuristics the way the ESPN path would.

/**
 * Role tag on a parsed NHL entry so the matcher can enforce
 * trigger-vs-role consistency (e.g. `goal_allowed` only matches
 * `role === "goalie"` entries).
 */
type NHLRole = "scorer" | "assister" | "goalie" | "shooter" | "hitter" | "hittee";

/**
 * Role-aware NHL triggers and the role of player entity that they target.
 * Legacy ambiguous `goal` is kept as a scorer-side alias for back-compat.
 */
const NHL_TRIGGER_ROLE: Record<string, NHLRole> = {
  goal_scored: "scorer",
  goal_allowed: "goalie",
  assist: "assister",
  goal: "scorer", // legacy: existing subs created before role-aware triggers
  shot_on_goal: "shooter",
  hit: "hitter",
};

/**
 * A parsed NHL play entry, one per (role, entity) pair. A single goal
 * with two assisters produces up to four entries: scorer, assister1,
 * assister2, and the goalie who let it in.
 */
export interface ParsedNHLEntry extends ParsedPlay {
  role: NHLRole;
}

/**
 * Normalize NHL `typeDescKey` to our snake_case trigger space.
 * "shot-on-goal" → "shot_on_goal", "blocked-shot" → "blocked_shot", etc.
 */
function nhlEventKey(typeDescKey: string): string {
  return typeDescKey.trim().toLowerCase().replace(/-/g, "_");
}

/**
 * Pure function: turn a normalized NHL play into zero, one, or more
 * parsed entries — one per (role, entity) pair.
 *
 * Goals fan out into scorer + each assist + goalie-in-net.
 * Shots/hits/etc. are single-role and produce one entry.
 */
export function parseNHLPlay(play: NHLPlay, event?: ESPNEvent): ParsedNHLEntry[] {
  const entries: ParsedNHLEntry[] = [];
  const key = nhlEventKey(play.eventType);
  if (!key) return entries;

  const desc = play.description || key.replace(/_/g, " ");

  if (key === "goal") {
    if (play.scorerId) {
      entries.push({
        role: "scorer",
        entityId: play.scorerId,
        entityIds: [play.scorerId],
        triggers: ["goal_scored", "goal"],
        description: formatAlertMessage("nhl", "goal_scored", desc, event),
      });
    }
    if (play.assist1Id) {
      entries.push({
        role: "assister",
        entityId: play.assist1Id,
        entityIds: [play.assist1Id],
        triggers: ["assist"],
        description: formatAlertMessage("nhl", "assist", desc, event),
      });
    }
    if (play.assist2Id) {
      entries.push({
        role: "assister",
        entityId: play.assist2Id,
        entityIds: [play.assist2Id],
        triggers: ["assist"],
        description: formatAlertMessage("nhl", "assist", desc, event),
      });
    }
    if (play.goalieInNetId) {
      entries.push({
        role: "goalie",
        entityId: play.goalieInNetId,
        entityIds: [play.goalieInNetId],
        triggers: ["goal_allowed"],
        description: formatAlertMessage("nhl", "goal_allowed", desc, event),
      });
    }
    return entries;
  }

  if (key === "shot_on_goal") {
    if (play.shooterId) {
      entries.push({
        role: "shooter",
        entityId: play.shooterId,
        entityIds: [play.shooterId],
        triggers: ["shot_on_goal"],
        description: formatAlertMessage("nhl", "shot_on_goal", desc, event),
      });
    }
    return entries;
  }

  if (key === "hit") {
    if (play.hitterId) {
      entries.push({
        role: "hitter",
        entityId: play.hitterId,
        entityIds: [play.hitterId],
        triggers: ["hit"],
        description: formatAlertMessage("nhl", "hit", desc, event),
      });
    }
    return entries;
  }

  if (key === "blocked_shot") {
    // On a blocked shot, `hittingPlayerId` would be empty; the NHL feed
    // puts the blocker in `details.playerId` via the RawPlay shape. We
    // already fallback-capture shooterId as the one who took the shot;
    // prefer that for single-role attribution.
    const who = play.shooterId ?? play.hitterId;
    if (who) {
      entries.push({
        role: "shooter",
        entityId: who,
        entityIds: [who],
        triggers: ["blocked_shot"],
        description: formatAlertMessage("nhl", "blocked_shot", desc, event),
      });
    }
    return entries;
  }

  if (key === "takeaway" || key === "giveaway") {
    const who = play.shooterId ?? play.scorerId ?? play.hitterId;
    if (who) {
      entries.push({
        role: "shooter",
        entityId: who,
        entityIds: [who],
        triggers: [key],
        description: formatAlertMessage("nhl", key, desc, event),
      });
    }
    return entries;
  }

  if (key === "penalty") {
    const who = play.hitterId ?? play.shooterId ?? play.scorerId;
    if (who) {
      entries.push({
        role: "hitter",
        entityId: who,
        entityIds: [who],
        triggers: ["penalty"],
        description: formatAlertMessage("nhl", "penalty", desc, event),
      });
    }
    return entries;
  }

  return entries;
}

/**
 * Pure predicate: does an NHL `ParsedNHLEntry` match a subscription?
 * Compares against `externalPlayerId` (the NHL api-web numeric id) rather
 * than ESPN's id. Enforces trigger-role consistency so a `goal_allowed`
 * sub on a scorer entry doesn't fire.
 */
export function matchesNHLEntry(
  entry: ParsedNHLEntry,
  sub: {
    externalPlayerId: string | null;
    trigger: string;
    active: boolean;
    league: string;
  }
): boolean {
  if (!sub.active) return false;
  if (sub.league !== "nhl") return false;
  if (!sub.externalPlayerId) return false;
  if (!entry.triggers.includes(sub.trigger)) return false;
  if (entry.entityId !== sub.externalPlayerId) return false;

  const expectedRole = NHL_TRIGGER_ROLE[sub.trigger];
  if (expectedRole && expectedRole !== entry.role) return false;
  return true;
}

/**
 * Match an NHL play (from api-web.nhle.com) against active NHL
 * subscriptions and dispatch alerts. Mirrors `matchAndAlertMLB`:
 * resolves role-specific player ids, compares against
 * `subscriptions.externalPlayerId`, dedupes via the alerts table.
 */
export async function matchAndAlertNHL(
  play: NHLPlay,
  gameId: string,
  event?: ESPNEvent
): Promise<number> {
  const entries = parseNHLPlay(play, event);
  if (entries.length === 0) return 0;

  const allNhlIds = Array.from(
    new Set(entries.map((e) => e.entityId).filter((x): x is string => !!x))
  );
  const allTriggers = Array.from(new Set(entries.flatMap((e) => e.triggers)));

  if (allNhlIds.length === 0 || allTriggers.length === 0) return 0;

  const matchingSubs = await db
    .select()
    .from(subscriptions)
    .where(
      and(
        eq(subscriptions.league, "nhl"),
        inArray(subscriptions.externalPlayerId, allNhlIds),
        inArray(subscriptions.trigger, allTriggers),
        eq(subscriptions.active, true)
      )
    );

  if (matchingSubs.length === 0) return 0;

  const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const matchingSubIds = matchingSubs.map((s) => s.id);
  const existing =
    matchingSubIds.length > 0 && play.playId
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
              eq(alerts.playId, play.playId),
              gte(alerts.sentAt, twentyFourHoursAgo)
            )
          )
      : [];

  let dispatched = 0;

  for (const sub of matchingSubs) {
    const entry = entries.find((e) =>
      matchesNHLEntry(e, {
        externalPlayerId: sub.externalPlayerId,
        trigger: sub.trigger,
        active: sub.active,
        league: sub.league,
      })
    );
    if (!entry) continue;

    const description = entry.description;

    const candidate: AlertLike = {
      subscriptionId: sub.id,
      gameId,
      playId: play.playId ?? "",
    };
    if (
      play.playId &&
      isDuplicateAlert(
        candidate,
        existing.map((e) => ({
          subscriptionId: e.subscriptionId,
          gameId: e.gameId,
          playId: e.playId ?? "",
        }))
      )
    ) {
      log.info("alerts.dedupe_skip", {
        subscriptionId: sub.id,
        gameId,
        playId: play.playId,
      });
      continue;
    }

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
          eventDescription: play.description || play.eventType,
          playId: play.playId ?? null,
        })
        .returning();
    } catch (err) {
      log.info("alerts.dedupe_race", {
        subscriptionId: sub.id,
        gameId,
        playId: play.playId,
        error: String(err),
      });
      continue;
    }

    if (sub.deliveryMethod === "push" || sub.deliveryMethod === "both") {
      await sendPushToUser(sub.userId, description, {
        subscriptionId: sub.id,
        alertId: alertRow?.id,
      });
    }
    if (sub.deliveryMethod === "sms" || sub.deliveryMethod === "both") {
      await sendSMSToUser(sub.userId, description);
    }
    dispatched++;
  }

  return dispatched;
}
