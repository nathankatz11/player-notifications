/**
 * ESPN unofficial API client.
 * No API key required. Polling interval: every 15-20s during live games.
 */

const ESPN_BASE = "https://site.api.espn.com/apis/site/v2/sports";

export type League = "nba" | "nfl" | "nhl" | "mlb" | "ncaafb" | "ncaamb" | "mls";

const LEAGUE_PATHS: Record<League, string> = {
  nba: "basketball/nba",
  nfl: "football/nfl",
  nhl: "hockey/nhl",
  mlb: "baseball/mlb",
  ncaafb: "football/college-football",
  ncaamb: "basketball/mens-college-basketball",
  mls: "soccer/usa.1",
};

export interface ESPNEvent {
  id: string;
  name: string;
  date: string;
  status: {
    type: { state: "pre" | "in" | "post" };
    displayClock: string;
    period: number;
  };
  competitions: Array<{
    competitors: Array<{
      team: { abbreviation: string; displayName: string; id: string };
      score: string;
      homeAway: "home" | "away";
    }>;
  }>;
}

export interface ESPNPlay {
  id: string;
  text: string;
  type: { id: string; text: string };
  participants?: Array<{
    athlete: { id: string; displayName: string };
  }>;
  team?: { id: string };
  scoreValue?: number;
}

/** Fetch today's scoreboard for a league */
export async function fetchScoreboard(league: League): Promise<{ events: ESPNEvent[] }> {
  const path = LEAGUE_PATHS[league];
  const res = await fetch(`${ESPN_BASE}/${path}/scoreboard`);

  if (!res.ok) {
    throw new Error(`ESPN scoreboard error: ${res.status} for ${league}`);
  }

  return res.json();
}

/** Fetch play-by-play summary for a specific game */
export async function fetchGameSummary(league: League, gameId: string): Promise<ESPNPlay[]> {
  const path = LEAGUE_PATHS[league];
  const res = await fetch(`${ESPN_BASE}/${path}/summary?event=${gameId}`);

  if (!res.ok) {
    throw new Error(`ESPN summary error: ${res.status} for game ${gameId}`);
  }

  const data = await res.json();

  // ESPN nests plays differently per sport
  if (data.plays) return data.plays;

  // NFL uses drives.previous[].plays
  if (data.drives?.previous) {
    return data.drives.previous.flatMap((d: { plays?: ESPNPlay[] }) => d.plays ?? []);
  }

  return [];
}

export interface ESPNTeam {
  id: string;
  name: string;
  abbreviation: string;
  logoUrl: string | null;
}

/** Fetch all teams for a league */
export async function fetchTeams(league: League): Promise<ESPNTeam[]> {
  const path = LEAGUE_PATHS[league];
  const limit = league === "ncaafb" || league === "ncaamb" ? "?limit=200" : "";
  const res = await fetch(`${ESPN_BASE}/${path}/teams${limit}`);

  if (!res.ok) {
    throw new Error(`ESPN teams error: ${res.status} for ${league}`);
  }

  const data = await res.json();
  const teamsRaw: Array<{ team: { id: string; displayName: string; abbreviation: string; logos?: Array<{ href: string }> } }> =
    data.sports?.[0]?.leagues?.[0]?.teams ?? [];

  return teamsRaw.map(({ team }) => ({
    id: team.id,
    name: team.displayName,
    abbreviation: team.abbreviation,
    logoUrl: team.logos?.[0]?.href ?? null,
  }));
}

/** Search ESPN for players/teams */
export async function searchEntities(
  query: string,
  _league?: League
): Promise<Array<{ id: string; name: string; type: string; imageUrl: string | null }>> {
  const url = `https://site.web.api.espn.com/apis/common/v3/search?query=${encodeURIComponent(query)}&limit=10&type=player,team`;
  const res = await fetch(url);

  if (!res.ok) {
    throw new Error(`ESPN search error: ${res.status}`);
  }

  const data = await res.json();
  const results: Array<{ id: string; name: string; type: string; imageUrl: string | null }> = [];

  for (const item of data.items ?? []) {
    results.push({
      id: String(item.id ?? ""),
      name: String(item.displayName ?? item.name ?? ""),
      type: String(item.type ?? "unknown"),
      imageUrl: item.logo ? String(item.logo) : null,
    });
  }

  return results;
}
