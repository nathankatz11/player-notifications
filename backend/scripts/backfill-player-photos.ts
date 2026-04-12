/**
 * One-off backfill: populate `subscriptions.photo_url` (and `team_id` if
 * missing) for existing player subscriptions. Run locally with the prod
 * DATABASE_URL exported:
 *
 *   export DATABASE_URL="postgres://..."
 *   npx tsx backend/scripts/backfill-player-photos.ts
 *
 * Safe to re-run; updates only rows where photo_url IS NULL.
 */

import { eq, and, isNull } from "drizzle-orm";
import { db } from "../lib/db";
import { subscriptions } from "../lib/db/schema";
import { fetchPlayerDetails, type League } from "../lib/espn";

async function main() {
  const rows = await db
    .select()
    .from(subscriptions)
    .where(and(eq(subscriptions.type, "player_stat"), isNull(subscriptions.photoUrl)));

  console.log(`Found ${rows.length} player subs missing photo_url`);

  let updated = 0;
  let skipped = 0;

  for (const row of rows) {
    const details = await fetchPlayerDetails(row.league as League, row.entityId);

    const patch: { photoUrl?: string; teamId?: string } = {};
    if (details.headshotUrl) patch.photoUrl = details.headshotUrl;
    if (details.teamId && !row.teamId) patch.teamId = details.teamId;

    if (Object.keys(patch).length === 0) {
      skipped++;
      console.log(`[skip] ${row.entityName} (${row.entityId}): no details from ESPN`);
      continue;
    }

    await db.update(subscriptions).set(patch).where(eq(subscriptions.id, row.id));
    updated++;
    console.log(
      `[ok]   ${row.entityName} (${row.entityId}): ${
        patch.photoUrl ? "photo" : ""
      }${patch.photoUrl && patch.teamId ? "+" : ""}${patch.teamId ? "team" : ""}`
    );
  }

  console.log(`\nDone. Updated ${updated}, skipped ${skipped}.`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
