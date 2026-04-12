import { NextRequest, NextResponse } from "next/server";
import { fetchScoreboard, type League } from "@/lib/espn";
import { enforceRateLimit } from "@/lib/rate-limit";

const VALID_LEAGUES = new Set<string>(["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"]);

/**
 * GET /api/scores/[league]
 * Fetch current scores for a specific league.
 */
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ league: string }> }
) {
  const limited = await enforceRateLimit(req, "scores", {
    limit: 60,
    windowMs: 60_000,
  });
  if (limited) return limited;

  const { league } = await params;

  if (!VALID_LEAGUES.has(league)) {
    return NextResponse.json(
      { error: `Invalid league. Must be one of: ${[...VALID_LEAGUES].join(", ")}` },
      { status: 400 }
    );
  }

  try {
    const data = await fetchScoreboard(league as League);
    const games = data.events.map((e) => ({
      id: e.id,
      name: e.name,
      startTime: e.date,
      status: e.status.type.state,
      clock: e.status.displayClock,
      period: e.status.period,
      competitors: e.competitions[0]?.competitors.map((c) => ({
        teamId: c.team.id,
        team: c.team.displayName,
        abbreviation: c.team.abbreviation,
        score: c.score,
        homeAway: c.homeAway,
      })),
    }));

    return NextResponse.json({ league, games });
  } catch {
    return NextResponse.json({ error: "Failed to fetch scores" }, { status: 502 });
  }
}
