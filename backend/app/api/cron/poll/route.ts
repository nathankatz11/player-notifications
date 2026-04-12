import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { games } from "@/lib/db/schema";
import { anyLiveGames, fetchScoreboard, fetchGameSummary, type League, type ESPNPlay } from "@/lib/espn";
import { matchAndAlert } from "@/lib/alerts";

const ACTIVE_LEAGUES: League[] = ["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"];

/**
 * GET /api/cron/poll
 * Vercel Cron Job: polls ESPN for live games and dispatches alerts.
 * Configured in vercel.json. Fast-paths (skips) when no games are live or
 * starting within 10 minutes.
 */
export async function GET(req: NextRequest) {
  const startedAt = Date.now();

  // Verify this is a legitimate cron call
  const authHeader = req.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Fast path: skip the expensive per-game polling when nothing is live.
  const liveCheckStart = Date.now();
  const hasLive = await anyLiveGames();
  const anyLiveGamesTookMs = Date.now() - liveCheckStart;

  if (!hasLive) {
    const duration_ms = Date.now() - startedAt;
    console.log(
      JSON.stringify({
        route: "cron/poll",
        skipped: true,
        reason: "no_live_games",
        anyLiveGamesTookMs,
        duration_ms,
        matched: 0,
        sent: 0,
      })
    );
    return Response.json(
      { skipped: true, reason: "no_live_games" },
      { status: 200 }
    );
  }

  let totalAlerts = 0;
  const results: Record<string, unknown> = {};

  for (const league of ACTIVE_LEAGUES) {
    try {
      const leagueAlerts = await pollLeague(league);
      results[league] = { alerts: leagueAlerts };
      totalAlerts += leagueAlerts;
    } catch (error) {
      console.error(`Error polling ${league}:`, error);
      results[league] = { error: String(error) };
    }
  }

  const duration_ms = Date.now() - startedAt;
  console.log(
    JSON.stringify({
      route: "cron/poll",
      skipped: false,
      anyLiveGamesTookMs,
      duration_ms,
      matched: totalAlerts,
      sent: totalAlerts,
    })
  );

  return NextResponse.json({
    polled: ACTIVE_LEAGUES.length,
    totalAlerts,
    results,
  });
}

async function pollLeague(league: League): Promise<number> {
  const scoreboard = await fetchScoreboard(league);
  const liveGames = scoreboard.events.filter((e) => e.status.type.state === "in");

  if (liveGames.length === 0) return 0;

  let alerts = 0;

  for (const game of liveGames) {
    alerts += await processGame(league, game.id);
  }

  return alerts;
}

async function processGame(league: League, gameId: string): Promise<number> {
  // Get stored game state
  const [gameState] = await db.select().from(games).where(eq(games.id, gameId));
  const lastPlayId = gameState?.lastPlayId ?? "";

  // Fetch latest plays
  const plays = await fetchGameSummary(league, gameId);
  if (plays.length === 0) return 0;

  // Find new plays since last checkpoint
  const lastPlayIndex = lastPlayId
    ? plays.findIndex((p: ESPNPlay) => p.id === lastPlayId)
    : -1;

  const newPlays = lastPlayIndex === -1 ? plays : plays.slice(lastPlayIndex + 1);
  if (newPlays.length === 0) return 0;

  // Process through alert engine
  let dispatched = 0;
  for (const play of newPlays) {
    dispatched += await matchAndAlert(play, gameId, league);
  }

  // Update checkpoint
  const latestPlayId = plays[plays.length - 1].id;
  await db
    .insert(games)
    .values({
      id: gameId,
      league,
      homeTeam: "",
      awayTeam: "",
      status: "in",
      lastPolledAt: new Date(),
      lastPlayId: latestPlayId,
    })
    .onConflictDoUpdate({
      target: games.id,
      set: {
        status: "in",
        lastPolledAt: new Date(),
        lastPlayId: latestPlayId,
      },
    });

  return dispatched;
}
