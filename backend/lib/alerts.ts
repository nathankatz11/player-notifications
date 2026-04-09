/**
 * Alert matching engine.
 * Matches ESPN plays to user subscriptions and dispatches notifications.
 */

import { eq, and } from "drizzle-orm";
import { db } from "./db";
import { subscriptions, alerts } from "./db/schema";
import { sendPushToUser } from "./apns";
import { sendSMSToUser } from "./twilio";
import type { ESPNPlay, League } from "./espn";

type Trigger = string;

interface ParsedPlay {
  entityId: string;
  trigger: Trigger;
  description: string;
}

/**
 * Match a play against active subscriptions and dispatch alerts.
 */
export async function matchAndAlert(
  play: ESPNPlay,
  gameId: string,
  league: League
): Promise<number> {
  const parsed = parsePlay(play, league);
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

function parsePlay(play: ESPNPlay, _league: League): ParsedPlay | null {
  const playType = play.type?.text?.toLowerCase() ?? "";
  const playerName = play.participants?.[0]?.athlete?.displayName ?? "Unknown";
  const playerId = play.participants?.[0]?.athlete?.id ?? "";
  const teamId = play.team?.id ?? "";

  if (!playerId && !teamId) return null;

  const trigger = TRIGGER_MAP[playType];
  if (!trigger) return null;

  return {
    entityId: playerId || teamId,
    trigger,
    description: `${playerName}: ${play.text}`,
  };
}
