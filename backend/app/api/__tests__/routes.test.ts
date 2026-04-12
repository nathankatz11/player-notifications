import { describe, it, expect, vi, beforeEach } from "vitest";
import { NextRequest } from "next/server";

/**
 * Integration-ish tests for StatShot route handlers.
 *
 * We import and invoke the exported route functions directly with a mock
 * NextRequest. The DB is fully mocked via a chainable Proxy that is awaitable
 * — the `_result` field controls what any terminal chain resolves to. The
 * rate limiter is mocked per-suite to either allow through or emit a 429.
 */

// ----- DB mock -------------------------------------------------------------

// Queue-based results: terminal awaits shift off the head. Tests push the
// expected rows in the order the handler will consume them.
const { dbResultQueue, enforceRateLimitMock } = vi.hoisted(() => {
  return {
    dbResultQueue: [] as unknown[],
    enforceRateLimitMock: vi.fn(async (..._args: unknown[]) => null as any),
  };
});

vi.mock("@/lib/db", () => {
  const makeChain = (): any => {
    const handler: ProxyHandler<any> = {
      get(_target, prop) {
        if (prop === "then") {
          return (resolve: (v: unknown) => void) => {
            const next = dbResultQueue.shift();
            resolve(next ?? []);
          };
        }
        return () => proxy;
      },
    };
    const proxy: any = new Proxy(function () {}, handler);
    return proxy;
  };
  const chain = makeChain();
  const mockDb = {
    select: () => chain,
    insert: () => chain,
    update: () => chain,
    delete: () => chain,
    execute: () => chain,
  };
  return { db: mockDb, getDb: () => mockDb };
});

// ----- Rate limit mock -----------------------------------------------------

vi.mock("@/lib/rate-limit", () => ({
  enforceRateLimit: (...args: unknown[]) => enforceRateLimitMock(...args),
  getClientIp: () => "127.0.0.1",
  rateLimit: async () => ({ allowed: true, remaining: 10, resetAt: Date.now() + 60_000 }),
}));

// Route handlers must be imported AFTER mocks are declared.
import { GET as alertsGET } from "@/app/api/alerts/route";
import { POST as subscriptionsPOST } from "@/app/api/subscriptions/route";
import { POST as registerPOST } from "@/app/api/register/route";
import { NextResponse } from "next/server";

function jsonPost(url: string, body: unknown): NextRequest {
  return new NextRequest(url, {
    method: "POST",
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  dbResultQueue.length = 0;
  enforceRateLimitMock.mockImplementation(async () => null);
});

// ----- GET /api/alerts -----------------------------------------------------

describe("GET /api/alerts", () => {
  it("returns 400 when userId query is missing", async () => {
    const req = new NextRequest("http://localhost/api/alerts?limit=10");
    const res = await alertsGET(req);
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toBe("Invalid request");
  });

  it("returns 400 when limit > 100", async () => {
    const req = new NextRequest("http://localhost/api/alerts?userId=u1&limit=500");
    const res = await alertsGET(req);
    expect(res.status).toBe(400);
  });

  it("returns 400 when cursor is malformed", async () => {
    const req = new NextRequest(
      "http://localhost/api/alerts?userId=u1&cursor=not-a-date"
    );
    const res = await alertsGET(req);
    expect(res.status).toBe(400);
  });

  it("returns { alerts, nextCursor: <iso> } when page is full", async () => {
    const now = new Date("2025-01-01T00:00:00.000Z");
    const rows = Array.from({ length: 3 }).map((_, i) => ({
      id: `a${i}`,
      userId: "u1",
      sentAt: new Date(now.getTime() - i * 1000),
      message: "m",
    }));
    dbResultQueue.push(rows);

    const req = new NextRequest("http://localhost/api/alerts?userId=u1&limit=3");
    const res = await alertsGET(req);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.alerts).toHaveLength(3);
    expect(body.nextCursor).toBe(rows[2].sentAt.toISOString());
  });

  it("returns nextCursor: null when page is not full", async () => {
    const rows = [
      {
        id: "a0",
        userId: "u1",
        sentAt: new Date("2025-01-01T00:00:00.000Z"),
        message: "m",
      },
    ];
    dbResultQueue.push(rows);

    const req = new NextRequest("http://localhost/api/alerts?userId=u1&limit=50");
    const res = await alertsGET(req);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.alerts).toHaveLength(1);
    expect(body.nextCursor).toBeNull();
  });
});

// ----- POST /api/subscriptions ---------------------------------------------

describe("POST /api/subscriptions", () => {
  const validBody = {
    userId: "11111111-1111-1111-1111-111111111111",
    type: "player_stat",
    league: "nba",
    entityId: "p-30",
    entityName: "Stephen Curry",
    trigger: "three_pointer",
    deliveryMethod: "push",
  };

  it("returns 400 on malformed body (missing fields)", async () => {
    const req = jsonPost("http://localhost/api/subscriptions", { userId: "u1" });
    const res = await subscriptionsPOST(req);
    expect(res.status).toBe(400);
  });

  it("returns 400 when league is unknown", async () => {
    const req = jsonPost("http://localhost/api/subscriptions", {
      ...validBody,
      league: "curling",
    });
    const res = await subscriptionsPOST(req);
    expect(res.status).toBe(400);
  });

  it("returns 400 when deliveryMethod is not push/sms/tweet", async () => {
    const req = jsonPost("http://localhost/api/subscriptions", {
      ...validBody,
      deliveryMethod: "carrier-pigeon",
    });
    const res = await subscriptionsPOST(req);
    expect(res.status).toBe(400);
  });

  it("returns 201 + new row on valid body (premium user skips free-tier check)", async () => {
    // 1) user lookup → premium user
    dbResultQueue.push([{ id: validBody.userId, plan: "premium" }]);
    // 2) insert().values().returning() → created row
    const newRow = {
      id: "sub-1",
      ...validBody,
      active: true,
      createdAt: new Date("2025-01-01T00:00:00.000Z"),
    };
    dbResultQueue.push([newRow]);

    const req = jsonPost("http://localhost/api/subscriptions", validBody);
    const res = await subscriptionsPOST(req);
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.id).toBe("sub-1");
    expect(body.entityId).toBe("p-30");
  });

  it("returns 429 when rate limit is exceeded", async () => {
    enforceRateLimitMock.mockImplementationOnce(async () =>
      NextResponse.json({ error: "Rate limit exceeded" }, { status: 429 })
    );

    const req = jsonPost("http://localhost/api/subscriptions", validBody);
    const res = await subscriptionsPOST(req);
    expect(res.status).toBe(429);
  });
});

// ----- POST /api/register --------------------------------------------------

describe("POST /api/register", () => {
  it("returns 400 when email isn't an email", async () => {
    const req = jsonPost("http://localhost/api/register", {
      email: "not-an-email",
      apnsToken: "tok",
    });
    const res = await registerPOST(req);
    expect(res.status).toBe(400);
  });

  it("returns 400 when apnsToken is empty string", async () => {
    const req = jsonPost("http://localhost/api/register", {
      email: "a@b.com",
      apnsToken: "",
    });
    const res = await registerPOST(req);
    expect(res.status).toBe(400);
  });

  it("updates apnsToken when user already exists (upsert branch)", async () => {
    // 1) select().from(users).where() → existing user
    dbResultQueue.push([{ id: "user-uuid", email: "a@b.com" }]);
    // 2) update().set().where() → resolves (value unused by handler)
    dbResultQueue.push([]);

    const req = jsonPost("http://localhost/api/register", {
      email: "a@b.com",
      apnsToken: "new-token",
    });
    const res = await registerPOST(req);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({ id: "user-uuid", updated: true });
  });

  it("inserts a new user when email is not found (insert branch)", async () => {
    // 1) select().from(users).where() → no existing user
    dbResultQueue.push([]);
    // 2) insert().values().returning() → newly created row
    dbResultQueue.push([{ id: "new-uuid", email: "new@b.com", apnsToken: "tok" }]);

    const req = jsonPost("http://localhost/api/register", {
      email: "new@b.com",
      apnsToken: "tok",
    });
    const res = await registerPOST(req);
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body).toEqual({ id: "new-uuid", created: true });
  });
});
