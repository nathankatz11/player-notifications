import { NextRequest, NextResponse } from "next/server";
import { searchEntities } from "@/lib/espn";
import type { League } from "@/lib/espn";

const VALID_LEAGUES = new Set<string>(["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"]);

/**
 * GET /api/search?q=lebron&league=nba
 * Search for players and teams via ESPN.
 */
export async function GET(req: NextRequest) {
  const q = req.nextUrl.searchParams.get("q");
  const league = req.nextUrl.searchParams.get("league");

  if (!q || q.length < 2) {
    return NextResponse.json(
      { error: "Query parameter 'q' is required (min 2 characters)" },
      { status: 400 }
    );
  }

  if (league && !VALID_LEAGUES.has(league)) {
    return NextResponse.json(
      { error: `Invalid league. Must be one of: ${[...VALID_LEAGUES].join(", ")}` },
      { status: 400 }
    );
  }

  try {
    const results = await searchEntities(q, league as League | undefined);
    return NextResponse.json({ results });
  } catch {
    return NextResponse.json({ error: "Search failed" }, { status: 500 });
  }
}
