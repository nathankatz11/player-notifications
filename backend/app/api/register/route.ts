import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { eq, and, ne } from "drizzle-orm";
import { enforceRateLimit } from "@/lib/rate-limit";

const registerSchema = z.object({
  email: z.string().email(),
  apnsToken: z.string().min(1),
});

/**
 * POST /api/register
 * Register a device with an APNs token. Creates or updates the user.
 */
export async function POST(req: NextRequest) {
  const limited = await enforceRateLimit(req, "register", {
    limit: 10,
    windowMs: 60 * 60_000,
  });
  if (limited) return limited;

  const json = await req.json().catch(() => null);
  const result = registerSchema.safeParse(json);
  if (!result.success) {
    return NextResponse.json(
      { error: "Invalid request", issues: result.error.issues },
      { status: 400 }
    );
  }
  const { email, apnsToken } = result.data;

  // Prevent duplicate pushes: if another user row already holds this APNs
  // token (e.g. a leftover test@statshot.app row from before SIWA), null it
  // out so only the current user receives pushes going forward.
  await db
    .update(users)
    .set({ apnsToken: null })
    .where(and(eq(users.apnsToken, apnsToken), ne(users.email, email)));

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
