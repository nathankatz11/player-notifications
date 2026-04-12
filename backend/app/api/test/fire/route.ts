import { NextRequest, NextResponse } from "next/server";
import { eq, and } from "drizzle-orm";
import { db } from "@/lib/db";
import { subscriptions, alerts } from "@/lib/db/schema";
import { sendPushToUser } from "@/lib/apns";
import { sendSMSToUser } from "@/lib/twilio";

/**
 * Authorize the request using the same CRON_SECRET bearer pattern
 * as /api/cron/poll. In dev (non-production) with CRON_SECRET unset,
 * allow the request so local testing still works.
 */
function authorize(req: NextRequest): NextResponse | null {
  const secret = process.env.CRON_SECRET;
  if (!secret) {
    if (process.env.NODE_ENV !== "production") {
      return null;
    }
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const authHeader = req.headers.get("authorization");
  if (authHeader !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  return null;
}

/**
 * GET /api/test/fire
 * Returns usage instructions for the test endpoint.
 */
export async function GET() {
  return NextResponse.json({
    usage: "POST /api/test/fire",
    description:
      "Simulate a play event and run it through the alert matching engine.",
    exampleBody: {
      entityId: "2",
      entityName: "Boston Celtics",
      trigger: "team_win",
      message:
        "🏀 WIN — Your Celtics beat the Lakers 112-108. Final.",
    },
    fields: {
      entityId: "The entity (player or team) ID to match against subscriptions",
      entityName: "Display name (for logging only)",
      trigger: "The trigger type to match (e.g. team_win, turnover, touchdown)",
      message: "The notification message to send to matched subscribers",
    },
  });
}

/**
 * POST /api/test/fire
 * Simulate a play event: find matching subscriptions, dispatch notifications,
 * and insert alert records.
 */
export async function POST(req: NextRequest) {
  const unauthorized = authorize(req);
  if (unauthorized) return unauthorized;

  const body = await req.json();
  const { entityId, entityName, trigger, message } = body;

  if (!entityId || !trigger || !message) {
    return NextResponse.json(
      { error: "Missing required fields: entityId, trigger, message" },
      { status: 400 }
    );
  }

  // Find matching active subscriptions
  const matchingSubs = await db
    .select()
    .from(subscriptions)
    .where(
      and(
        eq(subscriptions.entityId, entityId),
        eq(subscriptions.trigger, trigger),
        eq(subscriptions.active, true)
      )
    );

  if (matchingSubs.length === 0) {
    return NextResponse.json({
      matched: 0,
      dispatched: 0,
      details: [],
      note: `No active subscriptions found for entityId="${entityId}" trigger="${trigger}"`,
    });
  }

  const details: Array<{
    subscriptionId: string;
    userId: string;
    deliveryMethod: string;
    pushResult: boolean | null;
    smsResult: boolean | null;
    alertId: string;
  }> = [];

  let dispatched = 0;

  for (const sub of matchingSubs) {
    let pushResult: boolean | null = null;
    let smsResult: boolean | null = null;

    // Insert alert record first so we can attach its id to the push payload
    // (enables iOS deep-linking into AlertDetailView on notification tap).
    const [alert] = await db
      .insert(alerts)
      .values({
        subscriptionId: sub.id,
        userId: sub.userId,
        message,
        deliveryMethod: sub.deliveryMethod ?? "push",
        gameId: "test-game",
        eventDescription: `[TEST] ${entityName ?? entityId}: ${trigger}`,
      })
      .returning();

    // Send push notification
    if (sub.deliveryMethod === "push" || sub.deliveryMethod === "both") {
      pushResult = await sendPushToUser(sub.userId, message, {
        subscriptionId: sub.id,
        alertId: alert?.id,
      });
    }

    // Send SMS
    if (sub.deliveryMethod === "sms" || sub.deliveryMethod === "both") {
      smsResult = await sendSMSToUser(sub.userId, message);
    }

    details.push({
      subscriptionId: sub.id,
      userId: sub.userId,
      deliveryMethod: sub.deliveryMethod ?? "push",
      pushResult,
      smsResult,
      alertId: alert.id,
    });

    dispatched++;
  }

  return NextResponse.json({
    matched: matchingSubs.length,
    dispatched,
    details,
  });
}
