/**
 * ESPN unofficial API client.
 * No API key required. Polling interval: every 15-20s during live games.
 */

import { log } from "./logger";

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

const ALL_LEAGUES: League[] = ["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"];

// Module-level cache for anyLiveGames() — shared across warm invocations.
// Cold starts re-fetch (correct), and 2-minute TTL prevents thrashing ESPN
// if multiple calls happen within one cron execution.
const LIVE_CACHE_TTL_MS = 2 * 60 * 1000;
const START_SOON_WINDOW_MS = 10 * 60 * 1000;
let liveCache: { value: boolean; at: number } | null = null;

/**
 * Returns true if any supported league has a game in progress or starting
 * within the next 10 minutes. Used to fast-path skip cron polling when no
 * games are live. Results are cached for 2 minutes.
 */
export async function anyLiveGames(): Promise<boolean> {
  const now = Date.now();
  if (liveCache && now - liveCache.at < LIVE_CACHE_TTL_MS) {
    return liveCache.value;
  }

  // ESPN has no cross-sport scoreboard endpoint, so fan out.
  const results = await Promise.all(
    ALL_LEAGUES.map(async (league) => {
      try {
        const sb = await fetchScoreboard(league);
        return sb.events.some((e) => {
          const state = e.status?.type?.state;
          if (state === "in") return true;
          if (state === "pre") {
            const startMs = Date.parse(e.date);
            if (!Number.isNaN(startMs) && startMs - now <= START_SOON_WINDOW_MS && startMs - now >= 0) {
              return true;
            }
          }
          return false;
        });
      } catch (err) {
        // On ESPN error, bias toward polling (return true) so we don't silently
        // miss alerts due to a transient scoreboard failure.
        log.error("espn.scoreboard_fetch_failed", { league, error: String(err) });
        return true;
      }
    })
  );

  const value = results.some(Boolean);
  liveCache = { value, at: now };
  return value;
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
