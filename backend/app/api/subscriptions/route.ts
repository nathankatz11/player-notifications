import { NextRequest, NextResponse } from "next/server";
import { eq, and, count } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db";
import { subscriptions, users } from "@/lib/db/schema";
import { fetchPlayerDetails, type League } from "@/lib/espn";
import { enforceRateLimit } from "@/lib/rate-limit";

const FREE_TIER_LIMIT = 1000;

const createSubscriptionSchema = z.object({
  userId: z.string().min(1),
  type: z.enum(["player_stat", "team_event"]),
  league: z.enum(["nba", "nfl", "nhl", "mlb", "ncaafb", "ncaamb", "mls"]),
  entityId: z.string().min(1),
  entityName: z.string().min(1),
  trigger: z.string().min(1),
  deliveryMethod: z.enum(["push", "sms", "tweet"]).optional(),
});

/**
 * GET /api/subscriptions?userId=xxx
 * List all subscriptions for a user (active + paused). Paused subs are
 * still shown in the UI in a dimmed state so users can resume them; the
 * matching engine in alerts.ts already filters by active=true so paused
 * subs don't fire pushes.
 */
export async function GET(req: NextRequest) {
  const userId = req.nextUrl.searchParams.get("userId");
  if (!userId) {
    return NextResponse.json({ error: "userId is required" }, { status: 400 });
  }

  const subs = await db
    .select()
    .from(subscriptions)
    .where(eq(subscriptions.userId, userId));

  return NextResponse.json({ subscriptions: subs });
}

/**
 * POST /api/subscriptions
 * Create a new subscription. Enforces free tier limit (1000 max).
 */
export async function POST(req: NextRequest) {
  const limited = await enforceRateLimit(req, "subscriptions:create", {
    limit: 50,
    windowMs: 60 * 60_000,
  });
  if (limited) return limited;

  const json = await req.json().catch(() => null);
  const result = createSubscriptionSchema.safeParse(json);
  if (!result.success) {
    return NextResponse.json(
      { error: "Invalid request", issues: result.error.issues },
      { status: 400 }
    );
  }
  const { userId, type, league, entityId, entityName, trigger, deliveryMethod } = result.data;

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

  // For player subs, resolve the player's current team + headshot URL via
  // ESPN so the client can filter "my games today" and render a reliable
  // avatar. Best-effort — nulls are fine.
  let teamId: string | null = null;
  let photoUrl: string | null = null;
  if (type === "player_stat") {
    const details = await fetchPlayerDetails(league as League, entityId);
    teamId = details.teamId;
    photoUrl = details.headshotUrl;
  } else {
    teamId = entityId;
  }

  const [sub] = await db
    .insert(subscriptions)
    .values({
      userId,
      type,
      league,
      entityId,
      entityName,
      teamId,
      photoUrl,
      trigger,
      deliveryMethod: deliveryMethod ?? "push",
    })
    .returning();

  return NextResponse.json(sub, { status: 201 });
}
