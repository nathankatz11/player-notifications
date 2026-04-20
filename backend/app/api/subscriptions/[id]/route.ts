import { NextRequest, NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { db } from "@/lib/db";
import { subscriptions, alerts } from "@/lib/db/schema";

const updateSubscriptionSchema = z.object({
  active: z.boolean().optional(),
  trigger: z.string().min(1).optional(),
  deliveryMethod: z.string().min(1).optional(),
});

/**
 * PUT /api/subscriptions/[id]
 * Update a subscription (trigger, deliveryMethod, active status).
 */
export async function PUT(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const json = await req.json().catch(() => null);
  const result = updateSubscriptionSchema.safeParse(json);
  if (!result.success) {
    return NextResponse.json(
      { error: "Invalid request", issues: result.error.issues },
      { status: 400 }
    );
  }
  const body = result.data;

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
 * Hard delete a subscription and its related alert history.
 */
export async function DELETE(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;

  // Delete related alerts first (FK constraint)
  await db.delete(alerts).where(eq(alerts.subscriptionId, id));

  const deleted = await db
    .delete(subscriptions)
    .where(eq(subscriptions.id, id))
    .returning();

  if (deleted.length === 0) {
    return NextResponse.json({ error: "Subscription not found" }, { status: 404 });
  }

  return NextResponse.json({ deleted: true });
}
