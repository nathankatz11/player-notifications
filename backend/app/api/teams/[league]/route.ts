import { NextRequest, NextResponse } from "next/server";
import { fetchTeams, type League } from "@/lib/espn";

const VALID_LEAGUES = new Set<string>(["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"]);

/**
 * GET /api/teams/[league]
 * Fetch all teams for a specific league.
 */
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ league: string }> }
) {
  const { league } = await params;

  if (!VALID_LEAGUES.has(league)) {
    return NextResponse.json(
      { error: `Invalid league. Must be one of: ${[...VALID_LEAGUES].join(", ")}` },
      { status: 400 }
    );
  }

  try {
    const teams = await fetchTeams(league as League);
    return NextResponse.json({ league, teams });
  } catch {
    return NextResponse.json({ error: "Failed to fetch teams" }, { status: 502 });
  }
}
