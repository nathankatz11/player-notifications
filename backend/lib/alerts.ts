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
  entityId: string;
  trigger: Trigger;
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
 * Minimal shape of an alert row for dedupe. The dedupe key is
 * (subscriptionId, gameId, eventDescription) — the same play text from the
 * same game should not fire the same subscription twice.
 */
export interface AlertLike {
  subscriptionId: string;
  gameId: string;
  eventDescription: string;
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

  const { entityId, trigger, description } = parsed;

  // Find matching subscriptions
  const matchingSubs = await db
    .select()
    .from(subscriptions)
    .where(
      and(
        eq(subscriptions.entityId, entityId),
        eq(subscriptions.trigger, trigger),
        eq(subscriptions.active, true)
      )
    );

  if (matchingSubs.length === 0) return 0;

  let dispatched = 0;

  for (const sub of matchingSubs) {
    // Dedupe: if a cron invocation failed mid-iteration and the checkpoint
    // (games.lastPlayId) didn't advance, a retry will re-deliver the same
    // plays. Guard against that by checking the alerts table for a matching
    // (subscriptionId, gameId, eventDescription) row in the last 24 hours.
    // Check fires AFTER the match+trigger check so we don't pay a db roundtrip
    // on plays that wouldn't match anyway.
    const twentyFourHoursAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const existing = await db
      .select({ id: alerts.id })
      .from(alerts)
      .where(
        and(
          eq(alerts.subscriptionId, sub.id),
          eq(alerts.gameId, gameId),
          eq(alerts.eventDescription, play.text),
          gte(alerts.sentAt, twentyFourHoursAgo)
        )
      )
      .limit(1);

    if (existing.length > 0) {
      log.info("alerts.dedupe_skip", {
        subscriptionId: sub.id,
        gameId,
        eventDescription: play.text,
      });
      continue;
    }

    // Insert the alert row first so we have an `alertId` to embed in the push
    // payload (enables iOS deep-linking from the notification tap).
    const [alertRow] = await db
      .insert(alerts)
      .values({
        subscriptionId: sub.id,
        userId: sub.userId,
        message: description,
        deliveryMethod: sub.deliveryMethod ?? "push",
        gameId,
        eventDescription: play.text,
      })
      .returning();

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

  let dispatched = 0;

  for (const sub of candidates) {
    if (!matchesTeamResult(event, sub)) continue;

    const [existing] = await db
      .select({ id: alerts.id })
      .from(alerts)
      .where(and(eq(alerts.subscriptionId, sub.id), eq(alerts.gameId, event.id)))
      .limit(1);
    if (existing) continue;

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
  if (sub.entityId !== parsed.entityId) return false;
  if (sub.trigger !== parsed.trigger) return false;
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
 * Pure dedupe predicate: has an alert for this (subscription, game, event
 * description) already been recorded? Callers pass in the existing alerts
 * rows they've fetched — the predicate itself does no I/O.
 */
export function isDuplicateAlert(
  candidate: AlertLike,
  existing: readonly AlertLike[]
): boolean {
  return existing.some(
    (a) =>
      a.subscriptionId === candidate.subscriptionId &&
      a.gameId === candidate.gameId &&
      a.eventDescription === candidate.eventDescription
  );
}

export function parsePlay(play: ESPNPlay, league: League, event?: ESPNEvent): ParsedPlay | null {
  const playType = play.type?.text?.toLowerCase() ?? "";
  const playerName = play.participants?.[0]?.athlete?.displayName ?? "Unknown";
  const playerId = play.participants?.[0]?.athlete?.id ?? "";
  const teamId = play.team?.id ?? "";

  if (!playerId && !teamId) return null;

  let trigger: Trigger | undefined = TRIGGER_MAP[playType];

  // NBA text-based triggers
  if (!trigger) {
    const text = play.text?.toLowerCase() ?? "";
    if (text.includes("three point") && play.scoreValue === 3) trigger = "three_pointer";
    else if (text.includes("block")) trigger = "block";
    else if (playType.includes("dunk")) trigger = "dunk";
    else if (text.includes("steal")) trigger = "steal";
  }

  if (!trigger) return null;

  // Build a short play blurb: prefer player name + raw text, fall back to raw text
  const playText = playerName !== "Unknown"
    ? `${playerName} ${play.text}`
    : play.text;

  return {
    entityId: playerId || teamId,
    trigger,
    description: formatAlertMessage(league, trigger, playText, event),
  };
}
