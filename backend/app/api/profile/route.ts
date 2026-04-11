import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

/**
 * GET /api/profile?userId=...
 * Fetch a user's profile (phone, xHandle, plan).
 */
export async function GET(req: NextRequest) {
  const userId = req.nextUrl.searchParams.get("userId");
  if (!userId) {
    return NextResponse.json({ error: "userId is required" }, { status: 400 });
  }

  const [user] = await db.select().from(users).where(eq(users.id, userId));
  if (!user) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }

  return NextResponse.json({
    id: user.id,
    email: user.email,
    phone: user.phone ?? null,
    xHandle: user.xHandle ?? null,
    plan: user.plan,
  });
}

/**
 * PATCH /api/profile
 * Update a user's phone number and/or X handle.
 * Body: { userId, phone?, xHandle? }
 */
export async function PATCH(req: NextRequest) {
  const body = await req.json();
  const { userId, phone, xHandle } = body;

  if (!userId) {
    return NextResponse.json({ error: "userId is required" }, { status: 400 });
  }

  const updates: { phone?: string | null; xHandle?: string | null } = {};
  if (phone !== undefined) updates.phone = phone || null;
  if (xHandle !== undefined) updates.xHandle = xHandle ? xHandle.replace(/^@/, "") : null;

  if (Object.keys(updates).length === 0) {
    return NextResponse.json({ error: "No fields to update" }, { status: 400 });
  }

  const [updated] = await db
    .update(users)
    .set(updates)
    .where(eq(users.id, userId))
    .returning();

  if (!updated) {
    return NextResponse.json({ error: "User not found" }, { status: 404 });
  }

  return NextResponse.json({
    id: updated.id,
    phone: updated.phone ?? null,
    xHandle: updated.xHandle ?? null,
  });
}
