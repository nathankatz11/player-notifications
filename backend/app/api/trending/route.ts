import { NextRequest, NextResponse } from "next/server";
import {
  fetchScoreboard,
  fetchGameSummary,
  type League,
  type ESPNPlay,
} from "@/lib/espn";

const SUPPORTED_LEAGUES: League[] = ["nba", "nfl", "nhl", "mlb"];
const TOP_N = 15;

interface PlayerEntry {
  id: string;
  name: string;
  league: League;
  plays: number;
  team: string;
}

/**
 * GET /api/trending?league=nba
 * Returns the most active players from today's games based on play-by-play mentions.
 */
export async function GET(request: NextRequest) {
  const leagueParam = request.nextUrl.searchParams.get("league");

  const leagues: League[] = leagueParam && SUPPORTED_LEAGUES.includes(leagueParam as League)
    ? [leagueParam as League]
    : SUPPORTED_LEAGUES;

  // Map of playerId -> PlayerEntry
  const playerMap = new Map<string, PlayerEntry>();

  // We need team abbreviations keyed by team ID per league, extracted from the scoreboard
  const teamAbbrById = new Map<string, string>();

  await Promise.allSettled(
    leagues.map(async (league) => {
      let scoreboard;
      try {
        scoreboard = await fetchScoreboard(league);
      } catch {
        return; // skip league on error
      }

      // Build team abbreviation lookup from scoreboard competitors
      for (const event of scoreboard.events) {
        for (const comp of event.competitions[0]?.competitors ?? []) {
          teamAbbrById.set(comp.team.id, comp.team.abbreviation);
        }
      }

      // Fetch play-by-play for each game in parallel
      const gameIds = scoreboard.events.map((e) => e.id);

      await Promise.allSettled(
        gameIds.map(async (gameId) => {
          let plays: ESPNPlay[];
          try {
            plays = await fetchGameSummary(league, gameId);
          } catch {
            return;
          }

          for (const play of plays) {
            if (!play.participants?.length) continue;

            const teamId = play.team?.id;
            const teamAbbr = teamId ? (teamAbbrById.get(teamId) ?? "???") : "???";

            for (const participant of play.participants) {
              const pid = participant.athlete.id;
              const existing = playerMap.get(pid);

              if (existing) {
                existing.plays += 1;
              } else {
                playerMap.set(pid, {
                  id: pid,
                  name: participant.athlete.displayName,
                  league,
                  plays: 1,
                  team: teamAbbr,
                });
              }
            }
          }
        })
      );
    })
  );

  const trending = Array.from(playerMap.values())
    .sort((a, b) => b.plays - a.plays)
    .slice(0, TOP_N);

  return NextResponse.json({ trending });
}
