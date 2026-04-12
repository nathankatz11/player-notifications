import { NextRequest, NextResponse } from "next/server";
import { eq, desc, and, lt } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db";
import { alerts } from "@/lib/db/schema";

/**
 * GET /api/alerts?userId=xxx&limit=50&cursor=<ISO8601>
 *
 * Cursor-based pagination. Results are ordered by `sentAt` DESC; passing
 * `cursor` returns rows strictly older than that timestamp.
 *
 * Response:
 *   {
 *     alerts: AlertRow[],
 *     nextCursor: string | null  // ISO 8601 of last row, or null if no more
 *   }
 */
const querySchema = z.object({
  userId: z.string().min(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
  cursor: z
    .string()
    .datetime({ offset: true })
    .optional()
    .transform((v) => (v ? new Date(v) : undefined)),
});

export async function GET(req: NextRequest) {
  const parsed = querySchema.safeParse({
    userId: req.nextUrl.searchParams.get("userId") ?? undefined,
    limit: req.nextUrl.searchParams.get("limit") ?? undefined,
    cursor: req.nextUrl.searchParams.get("cursor") ?? undefined,
  });

  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid request", issues: parsed.error.issues },
      { status: 400 }
    );
  }

  const { userId, limit, cursor } = parsed.data;

  const whereClause = cursor
    ? and(eq(alerts.userId, userId), lt(alerts.sentAt, cursor))
    : eq(alerts.userId, userId);

  const userAlerts = await db
    .select()
    .from(alerts)
    .where(whereClause)
    .orderBy(desc(alerts.sentAt))
    .limit(limit);

  // If we filled the requested page, assume there may be more. Surface the
  // last row's `sentAt` as the next cursor; otherwise null.
  const nextCursor =
    userAlerts.length === limit
      ? userAlerts[userAlerts.length - 1].sentAt.toISOString()
      : null;

  return NextResponse.json({ alerts: userAlerts, nextCursor });
}
