import fetch from "node-fetch";
import { ESPNScoreboardResponse, ESPNPlay, League } from "./types";

const ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports";

/** Maps our league IDs to ESPN API path segments */
const LEAGUE_PATHS: Record<League, string> = {
  nba: "basketball/nba",
  nfl: "football/nfl",
  nhl: "hockey/nhl",
  mlb: "baseball/mlb",
  ncaafb: "football/college-football",
  ncaamb: "basketball/mens-college-basketball",
  mls: "soccer/usa.1",
};

/** Fetch today's scoreboard for a league */
export async function fetchScoreboard(league: League): Promise<ESPNScoreboardResponse> {
  const path = LEAGUE_PATHS[league];
  const url = `${ESPN_BASE}/${path}/scoreboard`;
  const res = await fetch(url);

  if (!res.ok) {
    throw new Error(`ESPN scoreboard error: ${res.status} for ${league}`);
  }

  return res.json() as Promise<ESPNScoreboardResponse>;
}

/** Fetch play-by-play summary for a specific game */
export async function fetchGameSummary(league: League, gameId: string): Promise<ESPNPlay[]> {
  const path = LEAGUE_PATHS[league];
  const url = `${ESPN_BASE}/${path}/summary?event=${gameId}`;
  const res = await fetch(url);

  if (!res.ok) {
    throw new Error(`ESPN summary error: ${res.status} for game ${gameId}`);
  }

  const data = await res.json() as Record<string, unknown>;

  // ESPN nests plays differently per sport — extract the plays array
  // This will need per-league parsing in the future
  const drives = data.drives as { previous?: Array<{ plays?: ESPNPlay[] }> } | undefined;
  const plays = data.plays as ESPNPlay[] | undefined;

  if (plays) {
    return plays;
  }

  // NFL uses drives.previous[].plays
  if (drives?.previous) {
    return drives.previous.flatMap((d) => d.plays ?? []);
  }

  return [];
}

/** Search ESPN for players/teams */
export async function searchEntities(
  query: string,
  league?: League
): Promise<Array<{ id: string; name: string; type: string; league: string; imageUrl: string | null }>> {
  // ESPN search endpoint
  const url = `https://site.web.api.espn.com/apis/common/v3/search?query=${encodeURIComponent(query)}&limit=10&type=player,team`;
  const res = await fetch(url);

  if (!res.ok) {
    throw new Error(`ESPN search error: ${res.status}`);
  }

  const data = await res.json() as Record<string, unknown>;
  const results: Array<{ id: string; name: string; type: string; league: string; imageUrl: string | null }> = [];

  // Parse search results — structure varies, this is a starting point
  const items = (data as { items?: Array<Record<string, unknown>> }).items ?? [];
  for (const item of items) {
    results.push({
      id: String(item.id ?? ""),
      name: String(item.displayName ?? item.name ?? ""),
      type: String(item.type ?? "unknown"),
      league: league ?? "unknown",
      imageUrl: item.logo ? String(item.logo) : null,
    });
  }

  return results;
}
