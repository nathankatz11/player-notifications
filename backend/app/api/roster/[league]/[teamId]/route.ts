import { NextRequest, NextResponse } from "next/server";
import { fetchTeamRoster, type League } from "@/lib/espn";
import { enforceRateLimit } from "@/lib/rate-limit";

const VALID_LEAGUES = new Set<string>([
  "nba",
  "nfl",
  "nhl",
  "mlb",
  "ncaafb",
  "ncaamb",
  "mls",
]);

/**
 * GET /api/roster/[league]/[teamId]
 * Returns the team's current roster (flat list of players).
 */
export async function GET(
  req: NextRequest,
  { params }: { params: Promise<{ league: string; teamId: string }> }
) {
  const limited = await enforceRateLimit(req, "roster", {
    limit: 60,
    windowMs: 60_000,
  });
  if (limited) return limited;

  const { league, teamId } = await params;

  if (!VALID_LEAGUES.has(league)) {
    return NextResponse.json(
      { error: `Invalid league. Must be one of: ${[...VALID_LEAGUES].join(", ")}` },
      { status: 400 }
    );
  }

  if (!teamId) {
    return NextResponse.json({ error: "teamId is required" }, { status: 400 });
  }

  try {
    const players = await fetchTeamRoster(league as League, teamId);
    return NextResponse.json({ league, teamId, players });
  } catch {
    return NextResponse.json({ error: "Failed to fetch roster" }, { status: 502 });
  }
}
