import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { fetchScoreboard, fetchGameSummary } from "../lib/espn";
import { matchAndAlert } from "../alerts/matchAndAlert";
import { League, GameDoc, ESPNPlay } from "../lib/types";

const db = admin.firestore();

/** All leagues we poll */
const ACTIVE_LEAGUES: League[] = ["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"];

/**
 * Scheduled function: polls ESPN for live games across all leagues.
 * Runs every minute via Cloud Scheduler (15s polling would need a different approach).
 * For each live game, fetches play-by-play and detects new plays since last poll.
 */
export const pollLiveGames = onSchedule("every 1 minutes", async () => {
  logger.info("Polling live games across all leagues");

  for (const league of ACTIVE_LEAGUES) {
    try {
      await pollLeague(league);
    } catch (err) {
      logger.error(`Error polling ${league}:`, err);
    }
  }
});

async function pollLeague(league: League): Promise<void> {
  const scoreboard = await fetchScoreboard(league);

  // Filter to live games only
  const liveGames = scoreboard.events.filter(
    (e) => e.status.type.state === "in"
  );

  if (liveGames.length === 0) {
    return;
  }

  logger.info(`${league}: ${liveGames.length} live games`);

  for (const game of liveGames) {
    try {
      await processGame(league, game.id);
    } catch (err) {
      logger.error(`Error processing game ${game.id}:`, err);
    }
  }
}

async function processGame(league: League, gameId: string): Promise<void> {
  // Get our stored game state
  const gameRef = db.collection("games").doc(gameId);
  const gameSnap = await gameRef.get();
  const gameData = gameSnap.data() as GameDoc | undefined;
  const lastPlayId = gameData?.lastPlayId ?? "";

  // Fetch latest plays
  const plays = await fetchGameSummary(league, gameId);

  if (plays.length === 0) {
    return;
  }

  // Find new plays since our last checkpoint
  const lastPlayIndex = lastPlayId
    ? plays.findIndex((p: ESPNPlay) => p.id === lastPlayId)
    : -1;

  const newPlays = lastPlayIndex === -1
    ? plays // First poll — process all plays (or just the last few to avoid spam)
    : plays.slice(lastPlayIndex + 1);

  if (newPlays.length === 0) {
    return;
  }

  // Process each new play through the alert matching engine
  for (const play of newPlays) {
    await matchAndAlert(play, gameId, league);
  }

  // Update our checkpoint
  const latestPlay = plays[plays.length - 1];
  await gameRef.set(
    {
      league,
      status: "in",
      lastPolledAt: admin.firestore.FieldValue.serverTimestamp(),
      lastPlayId: latestPlay.id,
    },
    { merge: true }
  );
}
