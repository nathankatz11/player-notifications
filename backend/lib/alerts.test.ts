import { describe, it, expect, vi, beforeEach } from "vitest";

// Mock the db module BEFORE importing alerts so the Proxy never tries to
// `neon(process.env.DATABASE_URL!)` during module load. The pure helpers
// we test don't touch the db at all — this is just defense against the
// top-level import graph.
vi.mock("./db", () => ({
  db: new Proxy(
    {},
    {
      get() {
        throw new Error(
          "db was accessed in a unit test — pure helpers should not hit the db"
        );
      },
    }
  ),
}));

// Mock apns/twilio so their top-level env reads don't blow up.
vi.mock("./apns", () => ({ sendPushToUser: vi.fn() }));
vi.mock("./twilio", () => ({ sendSMSToUser: vi.fn() }));

import {
  matchesSubscription,
  matchesTeamResult,
  isDuplicateAlert,
  parsePlay,
  type ParsedPlay,
  type SubscriptionLike,
  type AlertLike,
} from "./alerts";
import type { ESPNEvent, ESPNPlay } from "./espn";

// ---------- Fixtures -------------------------------------------------------

function makeSub(overrides: Partial<SubscriptionLike> = {}): SubscriptionLike {
  return {
    entityId: "player-123",
    trigger: "three_pointer",
    active: true,
    ...overrides,
  };
}

function makeParsed(overrides: Partial<ParsedPlay> & { trigger?: string } = {}): ParsedPlay {
  const { trigger, ...rest } = overrides;
  return {
    entityId: "player-123",
    triggers: trigger ? [trigger] : ["three_pointer"],
    description: "🏀 THREE — Steph Curry drains it.",
    ...rest,
  };
}

function makeGameEndEvent(
  subbedTeamId: string,
  subbedScore: string,
  otherTeamId: string,
  otherScore: string,
  state: "pre" | "in" | "post" = "post"
): ESPNEvent {
  return {
    id: "game-1",
    name: "Game 1",
    date: new Date().toISOString(),
    status: { type: { state }, displayClock: "0:00", period: 4 },
    competitions: [
      {
        competitors: [
          {
            team: {
              id: subbedTeamId,
              abbreviation: "SUB",
              displayName: "Subbed Team",
            },
            score: subbedScore,
            homeAway: "home",
          },
          {
            team: {
              id: otherTeamId,
              abbreviation: "OTH",
              displayName: "Other Team",
            },
            score: otherScore,
            homeAway: "away",
          },
        ],
      },
    ],
  };
}

// ---------- matchesSubscription (player-stat triggers) ---------------------

describe("matchesSubscription", () => {
  it("matches when entityId and trigger both match and sub is active", () => {
    expect(matchesSubscription(makeParsed(), makeSub())).toBe(true);
  });

  it("does NOT match when player ID differs", () => {
    expect(
      matchesSubscription(
        makeParsed({ entityId: "player-999" }),
        makeSub({ entityId: "player-123" })
      )
    ).toBe(false);
  });

  it("does NOT match when trigger type differs (dunk vs three_pointer)", () => {
    expect(
      matchesSubscription(
        makeParsed({ trigger: "three_pointer" }),
        makeSub({ trigger: "dunk" })
      )
    ).toBe(false);
  });

  it("does NOT match when subscription is inactive, even on exact entity+trigger match", () => {
    expect(
      matchesSubscription(makeParsed(), makeSub({ active: false }))
    ).toBe(false);
  });

  it("is strict about string equality (no fuzzy match on trigger)", () => {
    expect(
      matchesSubscription(
        makeParsed({ trigger: "three_pointer" }),
        makeSub({ trigger: "three" })
      )
    ).toBe(false);
  });

  it("matches team-entity plays (parsed.entityId comes from team when no player)", () => {
    const parsed = makeParsed({ entityId: "team-42", trigger: "turnover" });
    const sub = makeSub({ entityId: "team-42", trigger: "turnover" });
    expect(matchesSubscription(parsed, sub)).toBe(true);
  });
});

// ---------- matchesTeamResult (team_win / team_loss) -----------------------

describe("matchesTeamResult", () => {
  it("team_win fires when subbed team has higher score and game is final", () => {
    const event = makeGameEndEvent("team-A", "112", "team-B", "108", "post");
    const sub = makeSub({ entityId: "team-A", trigger: "team_win" });
    expect(matchesTeamResult(event, sub)).toBe(true);
  });

  it("team_win does NOT fire when subbed team has lower score", () => {
    const event = makeGameEndEvent("team-A", "100", "team-B", "120", "post");
    const sub = makeSub({ entityId: "team-A", trigger: "team_win" });
    expect(matchesTeamResult(event, sub)).toBe(false);
  });

  it("team_loss fires when subbed team has lower score and game is final", () => {
    const event = makeGameEndEvent("team-A", "95", "team-B", "110", "post");
    const sub = makeSub({ entityId: "team-A", trigger: "team_loss" });
    expect(matchesTeamResult(event, sub)).toBe(true);
  });

  it("team_loss does NOT fire when subbed team has higher score", () => {
    const event = makeGameEndEvent("team-A", "130", "team-B", "110", "post");
    const sub = makeSub({ entityId: "team-A", trigger: "team_loss" });
    expect(matchesTeamResult(event, sub)).toBe(false);
  });

  it("does NOT fire while game is still in progress (state = 'in')", () => {
    const event = makeGameEndEvent("team-A", "112", "team-B", "108", "in");
    const sub = makeSub({ entityId: "team-A", trigger: "team_win" });
    expect(matchesTeamResult(event, sub)).toBe(false);
  });

  it("does NOT fire before the game starts (state = 'pre')", () => {
    const event = makeGameEndEvent("team-A", "0", "team-B", "0", "pre");
    const sub = makeSub({ entityId: "team-A", trigger: "team_win" });
    expect(matchesTeamResult(event, sub)).toBe(false);
  });

  it("does NOT fire when the subbed team isn't in the competition", () => {
    const event = makeGameEndEvent("team-A", "112", "team-B", "108", "post");
    const sub = makeSub({ entityId: "team-Z", trigger: "team_win" });
    expect(matchesTeamResult(event, sub)).toBe(false);
  });

  it("does NOT fire on non-team triggers (e.g. dunk)", () => {
    const event = makeGameEndEvent("team-A", "112", "team-B", "108", "post");
    const sub = makeSub({ entityId: "team-A", trigger: "dunk" });
    expect(matchesTeamResult(event, sub)).toBe(false);
  });

  it("does NOT fire for inactive subscriptions", () => {
    const event = makeGameEndEvent("team-A", "112", "team-B", "108", "post");
    const sub = makeSub({
      entityId: "team-A",
      trigger: "team_win",
      active: false,
    });
    expect(matchesTeamResult(event, sub)).toBe(false);
  });
});

// ---------- isDuplicateAlert (dedupe) --------------------------------------

describe("isDuplicateAlert", () => {
  const candidate: AlertLike = {
    subscriptionId: "sub-1",
    gameId: "game-99",
    playId: "play-42",
  };

  it("returns false when no alerts exist for this subscription", () => {
    expect(isDuplicateAlert(candidate, [])).toBe(false);
  });

  it("returns true when an identical (sub, game, play) row already exists", () => {
    expect(isDuplicateAlert(candidate, [{ ...candidate }])).toBe(true);
  });

  it("returns false when gameId differs", () => {
    expect(
      isDuplicateAlert(candidate, [{ ...candidate, gameId: "game-100" }])
    ).toBe(false);
  });

  it("returns false when subscriptionId differs (same play, different user)", () => {
    expect(
      isDuplicateAlert(candidate, [{ ...candidate, subscriptionId: "sub-2" }])
    ).toBe(false);
  });

  it("returns false when playId differs (different play)", () => {
    expect(
      isDuplicateAlert(candidate, [{ ...candidate, playId: "play-43" }])
    ).toBe(false);
  });

  it("never dedupes when candidate has no playId (defensive fallback)", () => {
    const noPlay: AlertLike = { ...candidate, playId: "" };
    expect(isDuplicateAlert(noPlay, [noPlay])).toBe(false);
  });

  it("two events with the same playId produce only one alert row (simulated)", () => {
    const existing: AlertLike[] = [];
    const events = [candidate, { ...candidate }];
    let inserted = 0;
    for (const e of events) {
      if (!isDuplicateAlert(e, existing)) {
        existing.push(e);
        inserted++;
      }
    }
    expect(inserted).toBe(1);
    expect(existing).toHaveLength(1);
  });
});

// ---------- parsePlay (wiring sanity, not exhaustive) ----------------------

describe("parsePlay", () => {
  function makePlay(overrides: Partial<ESPNPlay> = {}): ESPNPlay {
    return {
      id: "play-1",
      text: "Shot made",
      type: { id: "1", text: "" },
      ...overrides,
    };
  }

  it("returns null when there's no player and no team (nothing to match)", () => {
    expect(parsePlay(makePlay(), "nba")).toBeNull();
  });

  it("returns null when no trigger can be inferred from the play type/text", () => {
    const play = makePlay({
      text: "a routine play",
      type: { id: "1", text: "unknown-play-type" },
      participants: [{ athlete: { id: "p-1", displayName: "Jim" } }],
    });
    expect(parsePlay(play, "nba")).toBeNull();
  });

  it("parses an NBA three-pointer into trigger=three_pointer with player entityId", () => {
    const play = makePlay({
      text: "Curry three point jumper",
      type: { id: "1", text: "Three Point Jumper" },
      participants: [{ athlete: { id: "p-30", displayName: "Stephen Curry" } }],
      scoreValue: 3,
    });
    const parsed = parsePlay(play, "nba");
    expect(parsed).not.toBeNull();
    expect(parsed!.entityId).toBe("p-30");
    expect(parsed!.triggers).toContain("three_pointer");
  });

  it("maps known play type strings via TRIGGER_MAP (e.g. turnover)", () => {
    const play = makePlay({
      text: "Bad pass",
      type: { id: "9", text: "Turnover" },
      participants: [{ athlete: { id: "p-7", displayName: "Player" } }],
    });
    const parsed = parsePlay(play, "nba");
    expect(parsed?.triggers).toContain("turnover");
  });

  it("falls back to team entityId when there's no player participant", () => {
    const play = makePlay({
      text: "Team turnover",
      type: { id: "9", text: "Turnover" },
      team: { id: "team-42" },
    });
    const parsed = parsePlay(play, "nba");
    expect(parsed?.entityId).toBe("team-42");
    expect(parsed?.triggers).toContain("turnover");
  });

  it("adds points_scored alongside three_pointer for NBA makes", () => {
    const play = makePlay({
      text: "Curry three point jumper",
      type: { id: "1", text: "Three Point Jumper" },
      participants: [{ athlete: { id: "p-30", displayName: "Stephen Curry" } }],
      scoreValue: 3,
    });
    const parsed = parsePlay(play, "nba");
    expect(parsed?.triggers).toEqual(
      expect.arrayContaining(["three_pointer", "points_scored"])
    );
  });

  it("does not false-positive 'block' on text like 'blockbuster'", () => {
    const play = makePlay({
      text: "blockbuster trade rumor",
      type: { id: "1", text: "Commentary" },
      participants: [{ athlete: { id: "p-1", displayName: "Player" } }],
    });
    const parsed = parsePlay(play, "nba");
    // No scoreValue and no real play type → no triggers at all.
    expect(parsed).toBeNull();
  });

  it("does not false-positive 'steal' on text like 'stealing time'", () => {
    const play = makePlay({
      text: "broadcaster stealing time from the booth",
      type: { id: "1", text: "Commentary" },
      participants: [{ athlete: { id: "p-1", displayName: "Player" } }],
    });
    const parsed = parsePlay(play, "nba");
    expect(parsed).toBeNull();
  });
});

// ---------- integration-ish: parsePlay ∘ matchesSubscription ---------------

describe("parsePlay + matchesSubscription together", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("a parsed NBA three triggers only the matching active player-stat sub", () => {
    const play: ESPNPlay = {
      id: "play-1",
      text: "Curry three point jumper",
      type: { id: "1", text: "Three Point Jumper" },
      participants: [{ athlete: { id: "p-30", displayName: "Stephen Curry" } }],
      scoreValue: 3,
    };
    const parsed = parsePlay(play, "nba")!;

    const subs: SubscriptionLike[] = [
      { entityId: "p-30", trigger: "three_pointer", active: true }, // hit
      { entityId: "p-30", trigger: "dunk", active: true }, // wrong trigger
      { entityId: "p-99", trigger: "three_pointer", active: true }, // wrong player
      { entityId: "p-30", trigger: "three_pointer", active: false }, // inactive
    ];

    const matched = subs.filter((s) => matchesSubscription(parsed, s));
    // Parsed NBA three fires both three_pointer AND points_scored.
    expect(matched.map((m) => m.trigger)).toContain("three_pointer");
    expect(matched.every((m) => m.active && m.entityId === "p-30")).toBe(true);
  });
});
