import { NextRequest, NextResponse } from "next/server";
import { eq, desc } from "drizzle-orm";
import { db } from "@/lib/db";
import { alerts } from "@/lib/db/schema";

/**
 * GET /api/alerts?userId=xxx
 * Fetch alert history for a user, ordered by most recent.
 */
export async function GET(req: NextRequest) {
  const userId = req.nextUrl.searchParams.get("userId");
  if (!userId) {
    return NextResponse.json({ error: "userId is required" }, { status: 400 });
  }

  const userAlerts = await db
    .select()
    .from(alerts)
    .where(eq(alerts.userId, userId))
    .orderBy(desc(alerts.sentAt))
    .limit(100);

  return NextResponse.json({ alerts: userAlerts });
}
