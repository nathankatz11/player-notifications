/**
 * One-off backfill: populate `subscriptions.position` and
 * `subscriptions.external_player_id` for existing MLB player subscriptions
 * created before those columns existed.
 *
 *   export DATABASE_URL="postgres://..."
 *   npx tsx backend/scripts/backfill-mlb-player-ids.ts
 *
 * Safe to re-run; only touches rows where one of the two fields is null.
 */

import { and, eq, isNull, or } from "drizzle-orm";
import { db } from "../lib/db";
import { subscriptions } from "../lib/db/schema";
import { fetchPlayerDetails } from "../lib/espn";
import { searchMLBPlayer } from "../lib/mlb";

async function main() {
  const rows = await db
    .select()
    .from(subscriptions)
    .where(
      and(
        eq(subscriptions.league, "mlb"),
        eq(subscriptions.type, "player_stat"),
        or(isNull(subscriptions.position), isNull(subscriptions.externalPlayerId))
      )
    );

  console.log(`Found ${rows.length} MLB player subs needing position/external_id`);

  let updated = 0;
  let skipped = 0;

  for (const row of rows) {
    // ESPN first — gets us display name, team, headshot, position. We already
    // stored teamId/photoUrl earlier via the POST handler; re-fetch position
    // in case it's the only null.
    const espn = await fetchPlayerDetails("mlb", row.entityId);
    const nameForLookup = espn.displayName ?? row.entityName;
    const teamName = espn.teamName ?? undefined;

    const mlb = await searchMLBPlayer(nameForLookup, teamName);

    const patch: Partial<typeof subscriptions.$inferInsert> = {};
    if (!row.position && (espn.position || mlb?.position)) {
      patch.position = mlb?.position ?? espn.position;
    }
    if (!row.externalPlayerId && mlb?.id) {
      patch.externalPlayerId = mlb.id;
    }

    if (Object.keys(patch).length === 0) {
      skipped++;
      console.log(`[skip] ${row.entityName} (${row.entityId}): no data from ESPN/MLB`);
      continue;
    }

    await db.update(subscriptions).set(patch).where(eq(subscriptions.id, row.id));
    updated++;
    const bits: string[] = [];
    if (patch.position) bits.push(`pos=${patch.position}`);
    if (patch.externalPlayerId) bits.push(`mlbId=${patch.externalPlayerId}`);
    console.log(`[ok]   ${row.entityName} (${row.entityId}): ${bits.join(" ")}`);
  }

  console.log(`\nDone. Updated ${updated}, skipped ${skipped}.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
