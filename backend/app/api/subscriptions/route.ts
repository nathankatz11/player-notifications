import { NextRequest, NextResponse } from "next/server";
import { eq, and, count } from "drizzle-orm";
import { db } from "@/lib/db";
import { subscriptions, users } from "@/lib/db/schema";

const FREE_TIER_LIMIT = 10;

/**
 * GET /api/subscriptions?userId=xxx
 * List active subscriptions for a user.
 */
export async function GET(req: NextRequest) {
  const userId = req.nextUrl.searchParams.get("userId");
  if (!userId) {
    return NextResponse.json({ error: "userId is required" }, { status: 400 });
  }

  const subs = await db
    .select()
    .from(subscriptions)
    .where(and(eq(subscriptions.userId, userId), eq(subscriptions.active, true)));

  return NextResponse.json({ subscriptions: subs });
}

/**
 * POST /api/subscriptions
 * Create a new subscription. Enforces free tier limit (3 max).
 */
export async function POST(req: NextRequest) {
  const body = await req.json();
  const { userId, type, league, entityId, entityName, trigger, deliveryMethod } = body;

  if (!userId || !type || !league || !entityId || !entityName || !trigger) {
    return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
  }

  // Check plan and enforce free tier limit
  const [user] = await db.select().from(users).where(eq(users.id, userId));
  if (!user) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }

  if (user.plan !== "premium") {
    const [{ value: activeCount }] = await db
      .select({ value: count() })
      .from(subscriptions)
      .where(and(eq(subscriptions.userId, userId), eq(subscriptions.active, true)));

    if (activeCount >= FREE_TIER_LIMIT) {
      return NextResponse.json(
        { error: `Free tier limited to ${FREE_TIER_LIMIT} active alerts. Upgrade to premium for unlimited.` },
        { status: 403 }
      );
    }
  }

  const [sub] = await db
    .insert(subscriptions)
    .values({
      userId,
      type,
      league,
      entityId,
      entityName,
      trigger,
      deliveryMethod: deliveryMethod ?? "push",
    })
    .returning();

  return NextResponse.json(sub, { status: 201 });
}
