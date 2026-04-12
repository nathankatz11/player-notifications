import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { eq } from "drizzle-orm";

const registerSchema = z.object({
  email: z.string().email(),
  apnsToken: z.string().min(1),
});

/**
 * POST /api/register
 * Register a device with an APNs token. Creates or updates the user.
 */
export async function POST(req: NextRequest) {
  const json = await req.json().catch(() => null);
  const result = registerSchema.safeParse(json);
  if (!result.success) {
    return NextResponse.json(
      { error: "Invalid request", issues: result.error.issues },
      { status: 400 }
    );
  }
  const { email, apnsToken } = result.data;

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
