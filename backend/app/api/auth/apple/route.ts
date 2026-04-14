import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createRemoteJWKSet, jwtVerify } from "jose";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { enforceRateLimit } from "@/lib/rate-limit";

/**
 * POST /api/auth/apple
 *
 * Verifies a Sign in with Apple identity token and upserts the user row keyed
 * by Apple's stable `sub` (`appleUserId`). The client MUST send both the raw
 * `identityToken` and the `appleUserId` it extracted client-side; the latter
 * is cross-checked against the verified JWT `sub` claim as paranoia.
 *
 * Apple only provides `email` / `fullName` on the *first* sign-in per
 * Apple-ID-per-app combination. On subsequent sign-ins, those fields are
 * absent and the client should simply omit them — we preserve whatever was
 * stored the first time.
 */

// Apple's published JWKS for SIWA token verification.
const APPLE_JWKS = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys")
);

// Bundle ID / client_id registered with Apple.
const APPLE_AUDIENCE = "com.statshot.app";
const APPLE_ISSUER = "https://appleid.apple.com";

const appleFullNameSchema = z
  .object({
    givenName: z.string().nullable().optional(),
    familyName: z.string().nullable().optional(),
  })
  .optional();

const appleAuthSchema = z.object({
  identityToken: z.string().min(1),
  appleUserId: z.string().min(1),
  email: z.string().email().nullable().optional(),
  fullName: appleFullNameSchema,
});

export async function POST(req: NextRequest) {
  const limited = await enforceRateLimit(req, "auth-apple", {
    limit: 10,
    windowMs: 60 * 60_000,
  });
  if (limited) return limited;

  const json = await req.json().catch(() => null);
  const result = appleAuthSchema.safeParse(json);
  if (!result.success) {
    return NextResponse.json(
      { error: "Invalid request", issues: result.error.issues },
      { status: 400 }
    );
  }
  const { identityToken, appleUserId, email } = result.data;

  // Verify JWT against Apple's JWKS. `jose` checks `exp` and signature.
  let verifiedSub: string;
  let verifiedEmail: string | undefined;
  try {
    const { payload } = await jwtVerify(identityToken, APPLE_JWKS, {
      issuer: APPLE_ISSUER,
      audience: APPLE_AUDIENCE,
    });
    if (typeof payload.sub !== "string" || payload.sub.length === 0) {
      return NextResponse.json(
        { error: "Invalid token: missing sub" },
        { status: 401 }
      );
    }
    verifiedSub = payload.sub;
    if (typeof payload.email === "string") {
      verifiedEmail = payload.email;
    }
  } catch (err) {
    console.warn(
      "[auth/apple] token verification failed:",
      err instanceof Error ? err.message : err
    );
    return NextResponse.json(
      {
        error: "Apple identity token verification failed",
        detail: err instanceof Error ? err.message : String(err),
      },
      { status: 401 }
    );
  }

  // Paranoia: the client-declared appleUserId must match the token's `sub`.
  if (verifiedSub !== appleUserId) {
    return NextResponse.json(
      { error: "appleUserId does not match verified token sub" },
      { status: 401 }
    );
  }

  // Prefer the email from the verified JWT claims; fall back to what the
  // client sent (it's only present on the first sign-in). After the first
  // sign-in, neither will be populated — that's expected and fine.
  const incomingEmail = verifiedEmail ?? email ?? null;

  // Upsert by appleUserId.
  const existing = await db
    .select()
    .from(users)
    .where(eq(users.appleUserId, verifiedSub));

  if (existing.length > 0) {
    const user = existing[0];
    // If we got an email this time and the stored one is a placeholder/missing,
    // persist it. Never overwrite a real email with null.
    if (incomingEmail && incomingEmail !== user.email) {
      await db
        .update(users)
        .set({ email: incomingEmail })
        .where(eq(users.id, user.id));
    }
    return NextResponse.json({
      userId: user.id,
      email: incomingEmail ?? user.email,
    });
  }

  // New user. Apple only provides email on first sign-in, so we persist it
  // now or never. If somehow absent, store a stable placeholder based on the
  // Apple sub so the NOT NULL constraint stays satisfied.
  const emailToStore = incomingEmail ?? `${verifiedSub}@privaterelay.appleid`;

  const [newUser] = await db
    .insert(users)
    .values({
      email: emailToStore,
      appleUserId: verifiedSub,
      plan: "free",
    })
    .returning();

  return NextResponse.json(
    { userId: newUser.id, email: newUser.email },
    { status: 201 }
  );
}
