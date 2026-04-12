import { sql } from "drizzle-orm";
import { db } from "@/lib/db";
import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

export interface RateLimitOptions {
  /** Maximum number of allowed calls within the window. */
  limit: number;
  /** Window length, in milliseconds. */
  windowMs: number;
}

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  /** Epoch ms at which the current window expires. */
  resetAt: number;
}

/**
 * Fixed-window rate limiter backed by Postgres.
 *
 * A single atomic UPSERT either:
 *  - inserts a new row (first request, or expired window) with count=1
 *  - increments the count when the existing row's window is still active
 *
 * The statement returns the effective window_start + count, which we use
 * to decide whether the caller is over the limit.
 */
export async function rateLimit(
  key: string,
  opts: RateLimitOptions
): Promise<RateLimitResult> {
  const { limit, windowMs } = opts;
  const now = new Date();
  const windowMsStr = String(Math.floor(windowMs));

  try {
    const rows = (await db.execute(sql`
      INSERT INTO rate_limits (key, window_start, count)
      VALUES (${key}, ${now}, 1)
      ON CONFLICT (key) DO UPDATE
      SET
        window_start = CASE
          WHEN rate_limits.window_start + (${windowMsStr}::bigint || ' milliseconds')::interval < ${now}
          THEN EXCLUDED.window_start
          ELSE rate_limits.window_start
        END,
        count = CASE
          WHEN rate_limits.window_start + (${windowMsStr}::bigint || ' milliseconds')::interval < ${now}
          THEN 1
          ELSE rate_limits.count + 1
        END
      RETURNING window_start, count
    `)) as unknown as Array<{ window_start: string | Date; count: number }>;

    const row = rows[0];
    if (!row) {
      // Shouldn't happen; fail open to avoid blocking callers on storage issues.
      return { allowed: true, remaining: limit - 1, resetAt: now.getTime() + windowMs };
    }

    const windowStart =
      row.window_start instanceof Date
        ? row.window_start
        : new Date(row.window_start);
    const resetAt = windowStart.getTime() + windowMs;
    const count = Number(row.count);
    const remaining = Math.max(0, limit - count);
    return {
      allowed: count <= limit,
      remaining,
      resetAt,
    };
  } catch {
    // Fail open on storage errors — we'd rather serve traffic than black-hole
    // legitimate users because the rate-limit table is unreachable.
    return { allowed: true, remaining: limit - 1, resetAt: now.getTime() + windowMs };
  }
}

/** Extract a best-effort client identifier from the request headers. */
export function getClientIp(req: NextRequest | Request): string {
  const fwd =
    req.headers.get("x-forwarded-for") ??
    req.headers.get("x-real-ip") ??
    "";
  const first = fwd.split(",")[0]?.trim();
  return first || "unknown";
}

/**
 * Build a 429 response with a `Retry-After` header. Returns `null` when the
 * request is allowed; callers use the returned response to short-circuit.
 */
export async function enforceRateLimit(
  req: NextRequest | Request,
  bucket: string,
  opts: RateLimitOptions
): Promise<NextResponse | null> {
  const ip = getClientIp(req);
  const key = `${bucket}:${ip}`;
  const result = await rateLimit(key, opts);
  if (result.allowed) return null;

  const retryAfterSeconds = Math.max(
    1,
    Math.ceil((result.resetAt - Date.now()) / 1000)
  );
  return NextResponse.json(
    { error: "Rate limit exceeded", resetAt: result.resetAt },
    {
      status: 429,
      headers: {
        "Retry-After": String(retryAfterSeconds),
        "X-RateLimit-Limit": String(opts.limit),
        "X-RateLimit-Remaining": "0",
        "X-RateLimit-Reset": String(Math.ceil(result.resetAt / 1000)),
      },
    }
  );
}
