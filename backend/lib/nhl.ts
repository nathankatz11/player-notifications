/**
 * NHL API client (api-web.nhle.com).
 *
 * Secondary data provider to ESPN for NHL games specifically — the NHL's
 * official play-by-play feed exposes *role-specific* player IDs on every
 * play (scorer, assister1, assister2, goalie-in-net, shooter, hitter,
 * hittee). ESPN's generic plays feed does not, so role-aware triggers
 * like "goal_allowed" on a goalie subscription can't reliably fire off
 * the ESPN feed.
 *
 * No auth required. Base URL: https://api-web.nhle.com/v1
 * Player search uses a separate host: https://search.d3.nhle.com/api/v1
 */

import { log } from "./logger";

const NHL_BASE = "https://api-web.nhle.com/v1";
const NHL_SEARCH_BASE = "https://search.d3.nhle.com/api/v1";

export interface NHLScheduleGame {
  gameId: string;
  state: string;
}

/**
 * A normalized NHL play derived from api-web.nhle.com's play-by-play feed.
 * One raw `plays[i]` entry maps to exactly one `NHLPlay`.
 *
 * - `playId` is `eventId` stringified — it's stable within a game.
 * - `eventType` is the raw `typeDescKey` (e.g. "goal", "shot-on-goal",
 *   "hit"). Consumers map it to our internal trigger system.
 * - All player-id fields are best-effort extracted from `details.*`.
 *   Any can be null if the feed omitted the role for that play type.
 */
export interface NHLPlay {
  playId: string;
  gameId: string;
  eventType: string;
  scorerId: string | null;
  assist1Id: string | null;
  assist2Id: string | null;
  /** Goalie who let a goal in (populated on `goal` events). */
  goalieInNetId: string | null;
  shooterId: string | null;
  hitterId: string | null;
  hitteeId: string | null;
  description: string;
  period: number;
}

interface RawScheduleResponse {
  gameWeek?: Array<{
    date?: string;
    games?: Array<{
      id?: number | string;
      gameState?: string;
    }>;
  }>;
  games?: Array<{
    id?: number | string;
    gameState?: string;
  }>;
}

interface RawPlay {
  eventId?: number | string;
  typeDescKey?: string;
  periodDescriptor?: { number?: number };
  period?: number;
  details?: {
    scoringPlayerId?: number | string;
    assist1PlayerId?: number | string;
    assist2PlayerId?: number | string;
    goalieInNetId?: number | string;
    shootingPlayerId?: number | string;
    hittingPlayerId?: number | string;
    hitteePlayerId?: number | string;
    playerId?: number | string;
    descKey?: string;
  };
}

interface RawPlayByPlayResponse {
  plays?: RawPlay[];
}

interface RawPlayerLanding {
  playerId?: number | string;
  position?: string;
  positionCode?: string;
  firstName?: { default?: string } | string;
  lastName?: { default?: string } | string;
}

interface RawPlayerSearchItem {
  playerId?: number | string;
  name?: string;
  teamAbbrev?: string;
  teamName?: string;
  positionCode?: string;
  active?: boolean;
}

function formatYMD(date: Date): string {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function asIdString(v: number | string | undefined | null): string | null {
  if (v == null) return null;
  const s = String(v).trim();
  return s.length > 0 ? s : null;
}

/**
 * Fetch the NHL schedule for a given date. Returns `{ gameId, state }`
 * for every game, where `state` is the raw `gameState`:
 * "FUT" | "PRE" | "LIVE" | "CRIT" | "OFF" | "FINAL".
 */
export async function fetchNHLSchedule(
  date: Date
): Promise<NHLScheduleGame[]> {
  const dateStr = formatYMD(date);
  const url = `${NHL_BASE}/schedule/${dateStr}`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      log.warn("nhl.schedule_fetch_failed", { status: res.status, dateStr });
      return [];
    }
    const data = (await res.json()) as RawScheduleResponse;
    const out: NHLScheduleGame[] = [];

    // The /schedule/{date} endpoint wraps games in `gameWeek[].games`.
    // Some older/alternate shapes use a flat `games[]` — handle both.
    const weeks = data.gameWeek ?? [];
    for (const wk of weeks) {
      for (const g of wk.games ?? []) {
        const id = asIdString(g.id);
        if (!id) continue;
        out.push({ gameId: id, state: g.gameState ?? "UNKNOWN" });
      }
    }
    for (const g of data.games ?? []) {
      const id = asIdString(g.id);
      if (!id) continue;
      // Avoid double-adding if weekly shape already surfaced it.
      if (out.some((e) => e.gameId === id)) continue;
      out.push({ gameId: id, state: g.gameState ?? "UNKNOWN" });
    }
    return out;
  } catch (err) {
    log.warn("nhl.schedule_fetch_error", { dateStr, error: String(err) });
    return [];
  }
}

/**
 * Fetch the play-by-play feed for a given NHL game and normalize to
 * `NHLPlay[]`. Pure network + transform; no I/O beyond the GET.
 */
export async function fetchNHLPlayByPlay(gameId: string): Promise<NHLPlay[]> {
  const url = `${NHL_BASE}/gamecenter/${gameId}/play-by-play`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      log.warn("nhl.pbp_fetch_failed", { status: res.status, gameId });
      return [];
    }
    const data = (await res.json()) as RawPlayByPlayResponse;
    return parseNHLPlayByPlayResponse(data, gameId);
  } catch (err) {
    log.warn("nhl.pbp_fetch_error", { gameId, error: String(err) });
    return [];
  }
}

/**
 * Exported for unit testing — turns a raw NHL play-by-play response into
 * our normalized `NHLPlay[]`. Pure function, no I/O.
 */
export function parseNHLPlayByPlayResponse(
  data: RawPlayByPlayResponse,
  gameId: string
): NHLPlay[] {
  const plays: NHLPlay[] = [];
  for (const p of data.plays ?? []) {
    const eventId = asIdString(p.eventId);
    const eventType = (p.typeDescKey ?? "").trim();
    if (!eventId || !eventType) continue;

    const d = p.details ?? {};
    const period =
      (typeof p.periodDescriptor?.number === "number"
        ? p.periodDescriptor.number
        : typeof p.period === "number"
        ? p.period
        : 0) || 0;

    plays.push({
      playId: eventId,
      gameId,
      eventType,
      scorerId: asIdString(d.scoringPlayerId),
      assist1Id: asIdString(d.assist1PlayerId),
      assist2Id: asIdString(d.assist2PlayerId),
      goalieInNetId: asIdString(d.goalieInNetId),
      shooterId: asIdString(d.shootingPlayerId),
      hitterId: asIdString(d.hittingPlayerId),
      hitteeId: asIdString(d.hitteePlayerId),
      description: d.descKey ?? eventType,
      period,
    });
  }
  return plays;
}

export interface NHLPlayerSearchResult {
  id: string;
  position: string | null;
}

/**
 * Search the NHL player index for a name. Optionally narrow to a team
 * (matched against `teamAbbrev` or `teamName` substring). Returns the top
 * match's NHL player ID + position, or null on miss / network error.
 *
 * The NHL API doesn't expose a query param for team filtering, so we pull
 * the candidate set and apply the team filter client-side.
 */
export async function searchNHLPlayer(
  name: string,
  teamAbbr?: string
): Promise<NHLPlayerSearchResult | null> {
  const url = `${NHL_SEARCH_BASE}/search/player?culture=en-us&limit=20&q=${encodeURIComponent(
    name
  )}&active=true`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      log.warn("nhl.player_search_failed", { status: res.status, name });
      return null;
    }
    const data = (await res.json()) as RawPlayerSearchItem[] | { suggestions?: RawPlayerSearchItem[] };
    // The real endpoint returns a bare array of items; some mirrors
    // wrap it in `{ suggestions: [...] }`. Accept both.
    const items: RawPlayerSearchItem[] = Array.isArray(data)
      ? data
      : data.suggestions ?? [];
    if (items.length === 0) return null;

    const teamLower = teamAbbr?.toLowerCase();
    let chosen = items[0];
    if (teamLower) {
      const preferred = items.find((it) => {
        const abbr = it.teamAbbrev?.toLowerCase() ?? "";
        const tname = it.teamName?.toLowerCase() ?? "";
        return abbr === teamLower || tname.includes(teamLower);
      });
      if (preferred) chosen = preferred;
    }

    const id = asIdString(chosen.playerId);
    if (!id) return null;
    return { id, position: chosen.positionCode ?? null };
  } catch (err) {
    log.warn("nhl.player_search_error", { name, error: String(err) });
    return null;
  }
}

/**
 * Fetch a single player's landing page and extract their position.
 * Used as a fallback path when `searchNHLPlayer` gave us an id but the
 * position wasn't present in the search result (older mirrors).
 */
export async function fetchNHLPlayerPosition(
  playerId: string
): Promise<string | null> {
  const url = `${NHL_BASE}/player/${playerId}/landing`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      log.warn("nhl.player_landing_failed", { status: res.status, playerId });
      return null;
    }
    const data = (await res.json()) as RawPlayerLanding;
    return data.positionCode ?? data.position ?? null;
  } catch (err) {
    log.warn("nhl.player_landing_error", { playerId, error: String(err) });
    return null;
  }
}
