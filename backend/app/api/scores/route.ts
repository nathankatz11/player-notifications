import { NextResponse } from "next/server";
import { fetchScoreboard, type League } from "@/lib/espn";

const ALL_LEAGUES: League[] = ["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"];

/**
 * GET /api/scores
 * Fetch current scores across all leagues.
 */
export async function GET() {
  const results: Record<string, unknown> = {};

  await Promise.allSettled(
    ALL_LEAGUES.map(async (league) => {
      try {
        const data = await fetchScoreboard(league);
        results[league] = data.events.map((e) => ({
          id: e.id,
          name: e.name,
          status: e.status.type.state,
          clock: e.status.displayClock,
          period: e.status.period,
          competitors: e.competitions[0]?.competitors.map((c) => ({
            team: c.team.displayName,
            abbreviation: c.team.abbreviation,
            score: c.score,
            homeAway: c.homeAway,
          })),
        }));
      } catch {
        results[league] = { error: "Failed to fetch" };
      }
    })
  );

  return NextResponse.json(results);
}
