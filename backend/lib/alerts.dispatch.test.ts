/**
 * Integration-ish tests for `dispatchTeamResult` — the team_win/team_loss
 * dispatcher wired into the cron. Uses a scripted mock of `./db` so we can
 * drive the full read+write path without a real Postgres.
 */
import { describe, it, expect, vi, beforeEach } from "vitest";

// ---- Scripted db mock -----------------------------------------------------
//
// The builder is chainable (select().from().where() / insert().values().returning())
// and just yields pre-queued arrays per call. Tests push the rows the next
// SELECT should return via `queueSelect`. INSERTs always succeed by default
// and record their payloads in `insertedRows` (tests assert on that).

interface InsertedRow {
  subscriptionId: string;
  userId: string;
  message: string;
  deliveryMethod: string;
  gameId: string;
  eventDescription: string;
  playId: string | null;
}

const state = {
  selectQueue: [] as unknown[][],
  insertedRows: [] as InsertedRow[],
  // When set, the NEXT insert throws (simulates unique-constraint race).
  nextInsertThrows: false,
};

function queueSelect(rows: unknown[]) {
  state.selectQueue.push(rows);
}

const selectBuilder = {
  from() {
    return this;
  },
  where() {
    const rows = state.selectQueue.shift() ?? [];
    return Promise.resolve(rows);
  },
};

const insertBuilder = {
  values(row: InsertedRow) {
    if (state.nextInsertThrows) {
      state.nextInsertThrows = false;
      return {
        returning: () =>
          Promise.reject(new Error("unique_violation")),
      };
    }
    state.insertedRows.push(row);
    return {
      returning: () =>
        Promise.resolve([
          {
            id: `alert-${state.insertedRows.length}`,
            ...row,
          },
        ]),
    };
  },
};

vi.mock("./db", () => ({
  db: {
    select: () => selectBuilder,
    insert: () => insertBuilder,
  },
}));

// Push / SMS side-effects: record invocations for assertions.
const pushCalls: Array<{ userId: string; message: string }> = [];
vi.mock("./apns", () => ({
  sendPushToUser: vi.fn(async (userId: string, message: string) => {
    pushCalls.push({ userId, message });
  }),
}));
vi.mock("./twilio", () => ({ sendSMSToUser: vi.fn() }));

import { dispatchTeamResult } from "./alerts";
import type { ESPNEvent } from "./espn";

// ---- Fixtures -------------------------------------------------------------

function makeFinalEvent(
  homeTeamId: string,
  homeScore: string,
  awayTeamId: string,
  awayScore: string,
  state: "pre" | "in" | "post" = "post"
): ESPNEvent {
  return {
    id: "game-1",
    name: "Home vs Away",
    date: new Date().toISOString(),
    status: { type: { state }, displayClock: "0:00", period: 4 },
    competitions: [
      {
        competitors: [
          {
            team: {
              id: homeTeamId,
              abbreviation: "HOM",
              displayName: "Home Team",
            },
            score: homeScore,
            homeAway: "home",
          },
          {
            team: {
              id: awayTeamId,
              abbreviation: "AWY",
              displayName: "Away Team",
            },
            score: awayScore,
            homeAway: "away",
          },
        ],
      },
    ],
  };
}

// Matches the shape of a subscriptions row the dispatcher reads.
interface SubRow {
  id: string;
  userId: string;
  entityId: string;
  trigger: "team_win" | "team_loss";
  active: boolean;
  deliveryMethod: "push" | "sms" | "both";
  league: string;
  type: "team_event";
  externalPlayerId: null;
}

function sub(overrides: Partial<SubRow>): SubRow {
  return {
    id: "sub-1",
    userId: "user-1",
    entityId: "team-A",
    trigger: "team_win",
    active: true,
    deliveryMethod: "push",
    league: "nba",
    type: "team_event",
    externalPlayerId: null,
    ...overrides,
  };
}

// ---- Tests ----------------------------------------------------------------

describe("dispatchTeamResult", () => {
  beforeEach(() => {
    state.selectQueue = [];
    state.insertedRows = [];
    state.nextInsertThrows = false;
    pushCalls.length = 0;
    vi.clearAllMocks();
  });

  it("happy path: team_win sub fires when their team wins a final game", async () => {
    const event = makeFinalEvent("team-A", "112", "team-B", "108", "post");
    // 1st SELECT: candidate subs (both teams in the matchup).
    queueSelect([sub({ id: "sub-A", entityId: "team-A", trigger: "team_win" })]);
    // 2nd SELECT: existing team_result alerts (none).
    queueSelect([]);

    const dispatched = await dispatchTeamResult(event, "nba");

    expect(dispatched).toBe(1);
    expect(state.insertedRows).toHaveLength(1);
    expect(state.insertedRows[0]).toMatchObject({
      subscriptionId: "sub-A",
      gameId: "game-1",
      playId: "team_result",
    });
    expect(state.insertedRows[0].message).toContain("won");
    expect(pushCalls).toHaveLength(1);
    expect(pushCalls[0].userId).toBe("user-1");
  });

  it("loss path: team_loss sub fires on their team losing a final game", async () => {
    const event = makeFinalEvent("team-A", "95", "team-B", "110", "post");
    queueSelect([sub({ id: "sub-A", entityId: "team-A", trigger: "team_loss" })]);
    queueSelect([]);

    const dispatched = await dispatchTeamResult(event, "nba");

    expect(dispatched).toBe(1);
    expect(state.insertedRows[0].message).toContain("lost");
    expect(state.insertedRows[0].playId).toBe("team_result");
  });

  it("dedupe: same sub across two cron runs only fires once", async () => {
    const event = makeFinalEvent("team-A", "112", "team-B", "108", "post");

    // Run 1: no existing alerts → fires.
    queueSelect([sub({ id: "sub-A", entityId: "team-A", trigger: "team_win" })]);
    queueSelect([]);
    expect(await dispatchTeamResult(event, "nba")).toBe(1);
    expect(state.insertedRows).toHaveLength(1);

    // Run 2: dedupe select now returns the already-sent row → skips.
    queueSelect([sub({ id: "sub-A", entityId: "team-A", trigger: "team_win" })]);
    queueSelect([{ subscriptionId: "sub-A" }]);
    expect(await dispatchTeamResult(event, "nba")).toBe(0);
    expect(state.insertedRows).toHaveLength(1); // still 1 — nothing new inserted
    expect(pushCalls).toHaveLength(1);
  });

  it("wrong trigger: team_win sub with team that LOST does not fire", async () => {
    // team-A lost; sub wants a win.
    const event = makeFinalEvent("team-A", "95", "team-B", "120", "post");
    queueSelect([sub({ id: "sub-A", entityId: "team-A", trigger: "team_win" })]);
    queueSelect([]); // (may or may not be consulted; queued defensively)

    const dispatched = await dispatchTeamResult(event, "nba");

    expect(dispatched).toBe(0);
    expect(state.insertedRows).toHaveLength(0);
    expect(pushCalls).toHaveLength(0);
  });

  it("inactive sub does not fire (even though DB query has active=true, defense in depth via matchesTeamResult)", async () => {
    const event = makeFinalEvent("team-A", "112", "team-B", "108", "post");
    // Simulate a stale row leak: dispatcher should still refuse to fire on
    // an inactive sub because matchesTeamResult checks sub.active.
    queueSelect([
      sub({
        id: "sub-A",
        entityId: "team-A",
        trigger: "team_win",
        active: false,
      }),
    ]);
    queueSelect([]);

    const dispatched = await dispatchTeamResult(event, "nba");

    expect(dispatched).toBe(0);
    expect(state.insertedRows).toHaveLength(0);
  });

  it("non-final game (state='in') does not fire", async () => {
    const event = makeFinalEvent("team-A", "80", "team-B", "70", "in");
    // Early return before any SELECT runs — queue nothing.

    const dispatched = await dispatchTeamResult(event, "nba");

    expect(dispatched).toBe(0);
    expect(state.insertedRows).toHaveLength(0);
    expect(pushCalls).toHaveLength(0);
  });
});
