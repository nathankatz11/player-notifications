import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { subscriptions } from "@/lib/db/schema";

/**
 * PUT /api/subscriptions/[id]
 * Update a subscription (trigger, deliveryMethod, active status).
 */
export async function PUT(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const body = await req.json();

  const updates: Record<string, unknown> = {};
  if (body.trigger !== undefined) updates.trigger = body.trigger;
  if (body.deliveryMethod !== undefined) updates.deliveryMethod = body.deliveryMethod;
  if (body.active !== undefined) updates.active = body.active;

  if (Object.keys(updates).length === 0) {
    return NextResponse.json({ error: "No fields to update" }, { status: 400 });
  }

  const [updated] = await db
    .update(subscriptions)
    .set(updates)
    .where(eq(subscriptions.id, id))
    .returning();

  if (!updated) {
    return NextResponse.json({ error: "Subscription not found" }, { status: 404 });
  }

  return NextResponse.json(updated);
}

/**
 * DELETE /api/subscriptions/[id]
 * Deactivate a subscription (soft delete).
 */
export async function DELETE(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;

  const [deactivated] = await db
    .update(subscriptions)
    .set({ active: false })
    .where(eq(subscriptions.id, id))
    .returning();

  if (!deactivated) {
    return NextResponse.json({ error: "Subscription not found" }, { status: 404 });
  }

  return NextResponse.json({ deactivated: true });
}
