/**
 * MLB Stats API client (statsapi.mlb.com).
 *
 * Used as a secondary data provider to ESPN for MLB games specifically —
 * the statsapi.mlb.com play-by-play feed exposes each play's batter AND
 * pitcher IDs explicitly (ESPN's does not), which is required for
 * role-aware triggers like "home run allowed" on pitcher subscriptions.
 *
 * No auth required. Base URL: https://statsapi.mlb.com/api/v1
 */

import { log } from "./logger";

const MLB_BASE = "https://statsapi.mlb.com/api/v1";

export interface MLBScheduleGame {
  gamePk: string;
  status: string;
}

/**
 * A normalized MLB play from statsapi.mlb.com's play-by-play feed,
 * independent of the underlying JSON shape. One raw `allPlays[i]` entry
 * produces one `MLBPlay`.
 *
 * - `playId` is synthesized as `${atBatIndex}.${playIndex ?? 0}` since the
 *   raw feed doesn't always include a stable GUID and we want deterministic
 *   dedupe keys.
 * - `eventType` is the snake-cased raw `result.event` (e.g. "home_run",
 *   "strikeout", "walk"). Consumers map it to our internal trigger system.
 * - `batterId` / `pitcherId` are best-effort extracted from `matchup.*.id`.
 * - `runnerId` is best-effort extracted for stolen-base-like events.
 */
export interface MLBPlay {
  playId: string;
  gameId: string;
  eventType: string;
  batterId: string | null;
  pitcherId: string | null;
  runnerId: string | null;
  description: string;
  inning: number;
  halfInning: "top" | "bottom";
}

interface ScheduleResponse {
  dates?: Array<{
    games?: Array<{
      gamePk?: number | string;
      status?: { abstractGameState?: string; detailedState?: string };
    }>;
  }>;
}

interface RawPlay {
  result?: {
    type?: string;
    event?: string;
    eventType?: string;
    description?: string;
  };
  about?: {
    inning?: number;
    halfInning?: string;
    atBatIndex?: number;
  };
  playEvents?: Array<{ index?: number }>;
  matchup?: {
    batter?: { id?: number | string };
    pitcher?: { id?: number | string };
  };
  runners?: Array<{
    details?: {
      runner?: { id?: number | string };
      event?: string;
    };
    movement?: { start?: string | null; end?: string | null };
  }>;
}

interface PlayByPlayResponse {
  allPlays?: RawPlay[];
}

interface PeopleSearchResponse {
  people?: Array<{
    id?: number | string;
    fullName?: string;
    primaryPosition?: { abbreviation?: string; code?: string; name?: string };
    currentTeam?: { name?: string };
  }>;
}

function formatYMD(date: Date): string {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, "0");
  const d = String(date.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * Fetch today's MLB schedule. Returns an array of `{ gamePk, status }`
 * for every regular-season + postseason game for the given date. `status`
 * is the abstract state — "Preview", "Live", or "Final".
 */
export async function fetchMLBSchedule(
  date: Date
): Promise<MLBScheduleGame[]> {
  const dateStr = formatYMD(date);
  const url = `${MLB_BASE}/schedule?sportId=1&date=${dateStr}&hydrate=linescore`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      log.warn("mlb.schedule_fetch_failed", { status: res.status, dateStr });
      return [];
    }
    const data = (await res.json()) as ScheduleResponse;
    const out: MLBScheduleGame[] = [];
    for (const day of data.dates ?? []) {
      for (const g of day.games ?? []) {
        if (g.gamePk == null) continue;
        out.push({
          gamePk: String(g.gamePk),
          status:
            g.status?.abstractGameState ??
            g.status?.detailedState ??
            "Unknown",
        });
      }
    }
    return out;
  } catch (err) {
    log.warn("mlb.schedule_fetch_error", { dateStr, error: String(err) });
    return [];
  }
}

/**
 * Convert MLB Stats API's display `result.event` strings into a
 * lowercase snake_cased eventType. "Home Run" → "home_run",
 * "Strikeout" → "strikeout", "Stolen Base 2B" → "stolen_base_2b".
 */
function normalizeEventType(raw: string | undefined): string {
  if (!raw) return "";
  return raw
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_|_$/g, "");
}

/**
 * Walk `allPlays` and flatten to our normalized `MLBPlay[]`. Each at-bat
 * produces exactly one row — we don't expand sub-events (pitch-by-pitch)
 * because our triggers fire at the at-bat granularity.
 *
 * For stolen-base-type events the raw feed doesn't always stamp a dedicated
 * at-bat row — SBs often arrive as `runners[].details.event` inside another
 * at-bat. We extract those as additional synthetic plays so a `stolen_base`
 * trigger on a runner can still fire.
 */
export async function fetchMLBPlayByPlay(gamePk: string): Promise<MLBPlay[]> {
  const url = `${MLB_BASE}/game/${gamePk}/playByPlay`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      log.warn("mlb.pbp_fetch_failed", { status: res.status, gamePk });
      return [];
    }
    const data = (await res.json()) as PlayByPlayResponse;
    return parsePlayByPlayResponse(data, gamePk);
  } catch (err) {
    log.warn("mlb.pbp_fetch_error", { gamePk, error: String(err) });
    return [];
  }
}

/**
 * Exported for unit testing — turns a raw statsapi playByPlay response
 * into our normalized `MLBPlay[]`. Pure function, no I/O.
 */
export function parsePlayByPlayResponse(
  data: PlayByPlayResponse,
  gamePk: string
): MLBPlay[] {
  const plays: MLBPlay[] = [];
  const rawPlays = data.allPlays ?? [];
  for (const p of rawPlays) {
    const atBatIndex =
      typeof p.about?.atBatIndex === "number" ? p.about.atBatIndex : -1;
    const lastEvent = p.playEvents?.[p.playEvents.length - 1];
    const playIndex =
      typeof lastEvent?.index === "number" ? lastEvent.index : 0;
    const batterId =
      p.matchup?.batter?.id != null ? String(p.matchup.batter.id) : null;
    const pitcherId =
      p.matchup?.pitcher?.id != null ? String(p.matchup.pitcher.id) : null;

    const halfRaw = (p.about?.halfInning ?? "").toLowerCase();
    const halfInning: "top" | "bottom" = halfRaw === "bottom" ? "bottom" : "top";
    const inning = typeof p.about?.inning === "number" ? p.about.inning : 0;

    const event = normalizeEventType(p.result?.event ?? p.result?.eventType);
    if (event) {
      plays.push({
        playId: `${atBatIndex}.${playIndex}`,
        gameId: gamePk,
        eventType: event,
        batterId,
        pitcherId,
        runnerId: null,
        description: p.result?.description ?? "",
        inning,
        halfInning,
      });
    }

    // Surface stolen-base-style runner events as their own synthetic plays.
    // The stats feed tags these on the `runners[]` array of any at-bat
    // during which a runner attempted to steal — not necessarily the at-bat
    // that resulted in the SB.
    for (let i = 0; i < (p.runners?.length ?? 0); i++) {
      const r = p.runners![i];
      const runnerEventRaw = r.details?.event ?? "";
      const runnerEvent = normalizeEventType(runnerEventRaw);
      if (!runnerEvent) continue;
      if (
        runnerEvent.startsWith("stolen_base") ||
        runnerEvent.startsWith("caught_stealing")
      ) {
        const runnerId =
          r.details?.runner?.id != null ? String(r.details.runner.id) : null;
        plays.push({
          playId: `${atBatIndex}.${playIndex}.r${i}`,
          gameId: gamePk,
          eventType: runnerEvent,
          batterId,
          pitcherId,
          runnerId,
          description: runnerEventRaw,
          inning,
          halfInning,
        });
      }
    }
  }
  return plays;
}

export interface MLBPlayerSearchResult {
  id: string;
  position: string | null;
}

/**
 * Search MLB Stats API for a player by name. Returns the top match's
 * `id` (stats-api numeric id, as a string) and primary position
 * abbreviation. If `teamName` is provided, prefers the match whose
 * currentTeam name contains it (useful for disambiguating common names).
 * Returns null on zero matches or network error.
 */
export async function searchMLBPlayer(
  name: string,
  teamName?: string
): Promise<MLBPlayerSearchResult | null> {
  const url = `${MLB_BASE}/people/search?names=${encodeURIComponent(name)}`;
  try {
    const res = await fetch(url);
    if (!res.ok) {
      log.warn("mlb.player_search_failed", { status: res.status, name });
      return null;
    }
    const data = (await res.json()) as PeopleSearchResponse;
    const people = data.people ?? [];
    if (people.length === 0) return null;

    const teamLower = teamName?.toLowerCase();
    let chosen = people[0];
    if (teamLower) {
      const preferred = people.find((p) =>
        p.currentTeam?.name?.toLowerCase().includes(teamLower)
      );
      if (preferred) chosen = preferred;
    }

    if (chosen.id == null) return null;
    return {
      id: String(chosen.id),
      position: chosen.primaryPosition?.abbreviation ?? null,
    };
  } catch (err) {
    log.warn("mlb.player_search_error", { name, error: String(err) });
    return null;
  }
}
