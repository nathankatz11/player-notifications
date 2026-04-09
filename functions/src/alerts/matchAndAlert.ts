import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { ESPNPlay, League, SubscriptionDoc, Trigger } from "../lib/types";
import { sendFCM } from "./sendFCM";
import { sendTwilioSMS } from "./sendTwilioSMS";

const db = admin.firestore();

/**
 * Matches a play against active subscriptions and dispatches alerts.
 * Core alert engine — parses play events and finds matching user subscriptions.
 */
export async function matchAndAlert(
  play: ESPNPlay,
  gameId: string,
  league: League
): Promise<void> {
  // Extract who was involved and what happened
  const parsed = parsePlay(play, league);
  if (!parsed) {
    return; // Unrecognizable play, skip
  }

  const { entityId, trigger, description } = parsed;

  // Query subscriptions matching this entity + trigger
  const subsSnap = await db
    .collection("subscriptions")
    .where("entityId", "==", entityId)
    .where("trigger", "==", trigger)
    .where("active", "==", true)
    .get();

  if (subsSnap.empty) {
    return;
  }

  logger.info(
    `Matched ${subsSnap.size} subscriptions for ${entityId} / ${trigger}`
  );

  // Dispatch alerts for each matching subscription
  for (const doc of subsSnap.docs) {
    const sub = doc.data() as SubscriptionDoc;

    if (sub.deliveryMethod === "push" || sub.deliveryMethod === "both") {
      await sendFCM(sub.userId, description);
    }

    if (sub.deliveryMethod === "sms" || sub.deliveryMethod === "both") {
      await sendTwilioSMS(sub.userId, description);
    }

    // Log the alert
    await db.collection("alerts").add({
      subscriptionId: doc.id,
      userId: sub.userId,
      message: description,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      deliveryMethod: sub.deliveryMethod,
      gameId,
      eventDescription: play.text,
    });
  }
}

interface ParsedPlay {
  entityId: string;
  trigger: Trigger;
  description: string;
}

/**
 * Parses an ESPN play into our trigger system.
 * TODO: Expand per-league parsing as ESPN formats differ by sport.
 */
function parsePlay(play: ESPNPlay, _league: League): ParsedPlay | null {
  const playType = play.type?.text?.toLowerCase() ?? "";
  const playerName = play.participants?.[0]?.athlete?.displayName ?? "Unknown";
  const playerId = play.participants?.[0]?.athlete?.id ?? "";
  const teamId = play.team?.id ?? "";

  if (!playerId && !teamId) {
    return null;
  }

  // Map ESPN play types to our trigger types
  const triggerMap: Record<string, Trigger> = {
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

  const trigger = triggerMap[playType];
  if (!trigger) {
    return null;
  }

  return {
    entityId: playerId || teamId,
    trigger,
    description: `${playerName}: ${play.text}`,
  };
}
