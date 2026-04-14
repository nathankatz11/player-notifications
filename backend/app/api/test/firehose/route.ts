import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";

const MAX_MINUTES = 240;

function authorize(req: NextRequest): NextResponse | null {
  const secret = process.env.CRON_SECRET;
  if (!secret) {
    if (process.env.NODE_ENV !== "production") return null;
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const auth = req.headers.get("authorization");
  if (auth !== `Bearer ${secret}`) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  return null;
}

const enableSchema = z.object({
  userId: z.string().min(1),
  minutes: z.number().int().positive().max(MAX_MINUTES).default(30),
});

/**
 * POST /api/test/firehose — body: { userId, minutes? }
 * Turn on firehose for the given user. Every new play in every live game
 * is dispatched as a push to this user until `firehose_until` elapses.
 * `minutes` is clamped to MAX_MINUTES to prevent accidental "forever on".
 */
export async function POST(req: NextRequest) {
  const unauthorized = authorize(req);
  if (unauthorized) return unauthorized;

  const body = await req.json().catch(() => null);
  const parsed = enableSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      { error: "Invalid request", issues: parsed.error.issues },
      { status: 400 }
    );
  }

  const { userId, minutes } = parsed.data;
  const until = new Date(Date.now() + minutes * 60_000);

  const [updated] = await db
    .update(users)
    .set({ firehoseUntil: until })
    .where(eq(users.id, userId))
    .returning({ id: users.id, firehoseUntil: users.firehoseUntil });

  if (!updated) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }

  return NextResponse.json({
    userId: updated.id,
    firehoseUntil: updated.firehoseUntil,
    minutes,
  });
}

/**
 * DELETE /api/test/firehose?userId=xxx
 * Turn off firehose immediately for the given user.
 */
export async function DELETE(req: NextRequest) {
  const unauthorized = authorize(req);
  if (unauthorized) return unauthorized;

  const userId = req.nextUrl.searchParams.get("userId");
  if (!userId) {
    return NextResponse.json({ error: "userId is required" }, { status: 400 });
  }

  const [updated] = await db
    .update(users)
    .set({ firehoseUntil: null })
    .where(eq(users.id, userId))
    .returning({ id: users.id });

  if (!updated) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }
  return NextResponse.json({ userId: updated.id, firehoseUntil: null });
}

/**
 * GET /api/test/firehose?userId=xxx
 * Read the current firehose_until for the given user.
 */
export async function GET(req: NextRequest) {
  const userId = req.nextUrl.searchParams.get("userId");
  if (!userId) {
    return NextResponse.json({ error: "userId is required" }, { status: 400 });
  }
  const [row] = await db
    .select({ id: users.id, firehoseUntil: users.firehoseUntil })
    .from(users)
    .where(eq(users.id, userId));
  if (!row) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }
  const now = new Date();
  const active = !!row.firehoseUntil && row.firehoseUntil > now;
  return NextResponse.json({
    userId: row.id,
    firehoseUntil: row.firehoseUntil,
    active,
  });
}
