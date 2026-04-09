/**
 * Alert matching engine.
 * Matches ESPN plays to user subscriptions and dispatches notifications.
 */

import { eq, and } from "drizzle-orm";
import { db } from "./db";
import { subscriptions, alerts } from "./db/schema";
import { sendPushToUser } from "./apns";
import { sendSMSToUser } from "./twilio";
import type { ESPNPlay, ESPNEvent, League } from "./espn";

type Trigger = string;

interface ParsedPlay {
  entityId: string;
  trigger: Trigger;
  description: string;
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
    // Send push notification
    if (sub.deliveryMethod === "push" || sub.deliveryMethod === "both") {
      await sendPushToUser(sub.userId, description);
    }

    // Send SMS (premium only — twilio.ts checks plan)
    if (sub.deliveryMethod === "sms" || sub.deliveryMethod === "both") {
      await sendSMSToUser(sub.userId, description);
    }

    // Log the alert
    await db.insert(alerts).values({
      subscriptionId: sub.id,
      userId: sub.userId,
      message: description,
      deliveryMethod: sub.deliveryMethod ?? "push",
      gameId,
      eventDescription: play.text,
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
};

function parsePlay(play: ESPNPlay, league: League, event?: ESPNEvent): ParsedPlay | null {
  const playType = play.type?.text?.toLowerCase() ?? "";
  const playerName = play.participants?.[0]?.athlete?.displayName ?? "Unknown";
  const playerId = play.participants?.[0]?.athlete?.id ?? "";
  const teamId = play.team?.id ?? "";

  if (!playerId && !teamId) return null;

  const trigger = TRIGGER_MAP[playType];
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
