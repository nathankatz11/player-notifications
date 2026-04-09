import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";
import { searchEntities } from "../lib/espn";
import { League } from "../lib/types";

const VALID_LEAGUES = new Set<string>(["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"]);

/**
 * HTTP function: search for players and teams via ESPN.
 * Called from the iOS app's AddAlertView search flow.
 *
 * GET /searchEntity?q=lebron&league=nba
 */
export const searchEntity = onRequest(async (req, res) => {
  if (req.method !== "GET") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const query = req.query.q as string | undefined;
  if (!query || query.length < 2) {
    res.status(400).json({ error: "Query parameter 'q' is required (min 2 characters)" });
    return;
  }

  const league = req.query.league as string | undefined;
  if (league && !VALID_LEAGUES.has(league)) {
    res.status(400).json({ error: `Invalid league. Must be one of: ${[...VALID_LEAGUES].join(", ")}` });
    return;
  }

  try {
    const results = await searchEntities(query, league as League | undefined);
    res.json({ results });
  } catch (err) {
    logger.error("Search failed:", err);
    res.status(500).json({ error: "Search failed" });
  }
});
