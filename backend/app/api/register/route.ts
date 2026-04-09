import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

/**
 * POST /api/register
 * Register a device with an APNs token. Creates or updates the user.
 */
export async function POST(req: NextRequest) {
  const body = await req.json();
  const { email, apnsToken } = body;

  if (!email || !apnsToken) {
    return NextResponse.json(
      { error: "email and apnsToken are required" },
      { status: 400 }
    );
  }

  // Upsert user by email
  const existing = await db.select().from(users).where(eq(users.email, email));

  if (existing.length > 0) {
    await db
      .update(users)
      .set({ apnsToken })
      .where(eq(users.id, existing[0].id));

    return NextResponse.json({ id: existing[0].id, updated: true });
  }

  const [newUser] = await db
    .insert(users)
    .values({ email, apnsToken })
    .returning();

  return NextResponse.json({ id: newUser.id, created: true }, { status: 201 });
}
