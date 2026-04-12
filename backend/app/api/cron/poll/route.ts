import { NextRequest, NextResponse } from "next/server";
import { eq, and } from "drizzle-orm";
import { db } from "@/lib/db";
import { games } from "@/lib/db/schema";
import {
  anyLiveGames,
  fetchScoreboard,
  fetchGameSummary,
  type League,
  type ESPNPlay,
  type ESPNEvent,
} from "@/lib/espn";
import { matchAndAlert, dispatchTeamResult } from "@/lib/alerts";
import { log } from "@/lib/logger";

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

  // Fast path: skip the expensive per-game polling when nothing is live AND
  // there are no games we previously saw live that still need finalization.
  const liveCheckStart = Date.now();
  const hasLive = await anyLiveGames();
  const anyLiveGamesTookMs = Date.now() - liveCheckStart;

  let pendingFinalization = 0;
  if (!hasLive) {
    const pending = await db
      .select({ id: games.id })
      .from(games)
      .where(eq(games.status, "in"));
    pendingFinalization = pending.length;
  }

  if (!hasLive && pendingFinalization === 0) {
    const duration_ms = Date.now() - startedAt;
    log.info("cron.poll", {
      route: "cron/poll",
      skipped: true,
      reason: "no_live_games",
      anyLiveGamesTookMs,
      duration_ms,
      matched: 0,
      sent: 0,
    });
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
      log.error("cron.poll.league_failed", { league, error: String(error) });
      results[league] = { error: String(error) };
    }
  }

  const duration_ms = Date.now() - startedAt;
  log.info("cron.poll", {
    route: "cron/poll",
    skipped: false,
    anyLiveGamesTookMs,
    duration_ms,
    matched: totalAlerts,
    sent: totalAlerts,
  });

  return NextResponse.json({
    polled: ACTIVE_LEAGUES.length,
    totalAlerts,
    results,
  });
}

async function pollLeague(league: League): Promise<number> {
  const scoreboard = await fetchScoreboard(league);

  // Games we previously saw live but may not yet have finalized.
  const stored = await db
    .select({ id: games.id, status: games.status })
    .from(games)
    .where(and(eq(games.league, league), eq(games.status, "in")));
  const pendingIds = new Set(stored.map((g) => g.id));

  // Process live games (for play-by-play) AND just-finished games we stored as
  // live (so team_win / team_loss fires once on the transition to final).
  const toProcess = scoreboard.events.filter((e) => {
    const state = e.status.type.state;
    if (state === "in") return true;
    if (state === "post" && pendingIds.has(e.id)) return true;
    return false;
  });

  if (toProcess.length === 0) return 0;

  let alerts = 0;
  for (const game of toProcess) {
    alerts += await processGame(league, game);
  }

  return alerts;
}

async function processGame(league: League, event: ESPNEvent): Promise<number> {
  const gameId = event.id;
  const state = event.status.type.state;

  // Get stored game state
  const [gameState] = await db.select().from(games).where(eq(games.id, gameId));
  const lastPlayId = gameState?.lastPlayId ?? "";

  // Fetch latest plays
  const plays = await fetchGameSummary(league, gameId);

  let dispatched = 0;

  if (plays.length > 0) {
    const lastPlayIndex = lastPlayId
      ? plays.findIndex((p: ESPNPlay) => p.id === lastPlayId)
      : -1;
    const newPlays = lastPlayIndex === -1 ? plays : plays.slice(lastPlayIndex + 1);

    for (const play of newPlays) {
      dispatched += await matchAndAlert(play, gameId, league, event);
    }
  }

  // Fire team_win / team_loss on transition to final. Dedupe lives inside
  // dispatchTeamResult via the alerts table.
  if (state === "post") {
    dispatched += await dispatchTeamResult(event, league);
  }

  const latestPlayId = plays.length > 0 ? plays[plays.length - 1].id : lastPlayId;
  await db
    .insert(games)
    .values({
      id: gameId,
      league,
      status: state === "post" ? "post" : "in",
      lastPolledAt: new Date(),
      lastPlayId: latestPlayId,
    })
    .onConflictDoUpdate({
      target: games.id,
      set: {
        status: state === "post" ? "post" : "in",
        lastPolledAt: new Date(),
        lastPlayId: latestPlayId,
      },
    });

  return dispatched;
}
