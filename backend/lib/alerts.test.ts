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
  parseMLBPlay,
  matchesMLBEntry,
  type ParsedPlay,
  type SubscriptionLike,
  type AlertLike,
} from "./alerts";
import type { ESPNEvent, ESPNPlay } from "./espn";
import { parsePlayByPlayResponse, type MLBPlay } from "./mlb";

// ---------- Fixtures -------------------------------------------------------

function makeSub(overrides: Partial<SubscriptionLike> = {}): SubscriptionLike {
  return {
    entityId: "player-123",
    trigger: "three_pointer",
    active: true,
    ...overrides,
  };
}

function makeParsed(
  overrides: Partial<ParsedPlay> & { trigger?: string } = {}
): ParsedPlay {
  const { trigger, ...rest } = overrides;
  const entityId = rest.entityId ?? "player-123";
  return {
    entityId,
    entityIds: rest.entityIds ?? [entityId],
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

// ---------- parseMLBPlay + matchesMLBEntry (role-aware MLB triggers) -------

describe("parseMLBPlay", () => {
  function makeMLBPlay(overrides: Partial<MLBPlay> = {}): MLBPlay {
    return {
      playId: "12.3",
      gameId: "gp-1",
      eventType: "home_run",
      batterId: "batter-1",
      pitcherId: "pitcher-1",
      runnerId: null,
      description: "Smith homers (3) on a fly ball to center field.",
      inning: 3,
      halfInning: "top",
      ...overrides,
    };
  }

  it("a home run produces two entries: batter (home_run_hit + legacy home_run) and pitcher (home_run_allowed)", () => {
    const entries = parseMLBPlay(makeMLBPlay());
    expect(entries).toHaveLength(2);

    const batter = entries.find((e) => e.role === "batter");
    expect(batter).toBeDefined();
    expect(batter!.entityId).toBe("batter-1");
    expect(batter!.triggers).toEqual(
      expect.arrayContaining(["home_run_hit", "home_run"])
    );

    const pitcher = entries.find((e) => e.role === "pitcher");
    expect(pitcher).toBeDefined();
    expect(pitcher!.entityId).toBe("pitcher-1");
    expect(pitcher!.triggers).toEqual(["home_run_allowed"]);
    // Pitcher entry should NOT carry the batter-side triggers.
    expect(pitcher!.triggers).not.toContain("home_run_hit");
    expect(pitcher!.triggers).not.toContain("home_run");
  });

  it("a strikeout produces a batter entry (strikeout_batting + legacy strikeout) and a pitcher entry (strikeout_pitched)", () => {
    const entries = parseMLBPlay(
      makeMLBPlay({ eventType: "strikeout", description: "Smith strikes out swinging." })
    );
    expect(entries).toHaveLength(2);
    const batter = entries.find((e) => e.role === "batter");
    expect(batter!.triggers).toEqual(
      expect.arrayContaining(["strikeout_batting", "strikeout"])
    );
    const pitcher = entries.find((e) => e.role === "pitcher");
    expect(pitcher!.triggers).toEqual(["strikeout_pitched"]);
  });

  it("a walk produces a batter-only entry (legacy walk trigger)", () => {
    const entries = parseMLBPlay(
      makeMLBPlay({ eventType: "walk", description: "Smith walks." })
    );
    expect(entries).toHaveLength(1);
    expect(entries[0].role).toBe("batter");
    expect(entries[0].triggers).toEqual(["walk"]);
  });

  it("a stolen base produces a runner-only entry", () => {
    const entries = parseMLBPlay(
      makeMLBPlay({
        eventType: "stolen_base_2b",
        runnerId: "runner-9",
        description: "Smith steals 2nd.",
      })
    );
    expect(entries).toHaveLength(1);
    expect(entries[0].role).toBe("runner");
    expect(entries[0].entityId).toBe("runner-9");
    expect(entries[0].triggers).toEqual(["stolen_base"]);
  });

  it("omits the batter entry when the play has no batterId (defensive)", () => {
    const entries = parseMLBPlay(
      makeMLBPlay({ eventType: "home_run", batterId: null })
    );
    // Only the pitcher entry is produced.
    expect(entries).toHaveLength(1);
    expect(entries[0].role).toBe("pitcher");
  });

  it("returns [] for an unrecognized event", () => {
    const entries = parseMLBPlay(makeMLBPlay({ eventType: "field_out" }));
    expect(entries).toEqual([]);
  });
});

describe("matchesMLBEntry (role-aware matching)", () => {
  function hrPlay(): MLBPlay {
    return {
      playId: "12.3",
      gameId: "gp-1",
      eventType: "home_run",
      batterId: "batter-42",
      pitcherId: "pitcher-7",
      runnerId: null,
      description: "Jones homers.",
      inning: 1,
      halfInning: "top",
    };
  }

  it("pitcher sub with home_run_allowed fires when the pitcher's id matches the pitcher on the HR", () => {
    const entries = parseMLBPlay(hrPlay());
    const pitcher = entries.find((e) => e.role === "pitcher")!;
    expect(
      matchesMLBEntry(pitcher, {
        externalPlayerId: "pitcher-7",
        trigger: "home_run_allowed",
        active: true,
        league: "mlb",
      })
    ).toBe(true);
  });

  it("pitcher sub with home_run_allowed does NOT fire for a different pitcher", () => {
    const entries = parseMLBPlay(hrPlay());
    const pitcher = entries.find((e) => e.role === "pitcher")!;
    expect(
      matchesMLBEntry(pitcher, {
        externalPlayerId: "pitcher-999",
        trigger: "home_run_allowed",
        active: true,
        league: "mlb",
      })
    ).toBe(false);
  });

  it("batter sub with home_run_hit fires, but does NOT fire for home_run_allowed", () => {
    const entries = parseMLBPlay(hrPlay());
    const batter = entries.find((e) => e.role === "batter")!;
    expect(
      matchesMLBEntry(batter, {
        externalPlayerId: "batter-42",
        trigger: "home_run_hit",
        active: true,
        league: "mlb",
      })
    ).toBe(true);
    // home_run_allowed is a pitcher-role trigger — should NOT match a batter entry
    expect(
      matchesMLBEntry(batter, {
        externalPlayerId: "batter-42",
        trigger: "home_run_allowed",
        active: true,
        league: "mlb",
      })
    ).toBe(false);
  });

  it("legacy home_run sub still fires for a batter HR (backward compat)", () => {
    const entries = parseMLBPlay(hrPlay());
    const batter = entries.find((e) => e.role === "batter")!;
    expect(
      matchesMLBEntry(batter, {
        externalPlayerId: "batter-42",
        trigger: "home_run",
        active: true,
        league: "mlb",
      })
    ).toBe(true);
  });

  it("strikeout_pitched fires for the pitcher; strikeout_batting fires for the batter", () => {
    const kPlay: MLBPlay = {
      playId: "5.1",
      gameId: "gp-1",
      eventType: "strikeout",
      batterId: "batter-11",
      pitcherId: "pitcher-22",
      runnerId: null,
      description: "Jones strikes out.",
      inning: 2,
      halfInning: "bottom",
    };
    const entries = parseMLBPlay(kPlay);
    const batter = entries.find((e) => e.role === "batter")!;
    const pitcher = entries.find((e) => e.role === "pitcher")!;

    expect(
      matchesMLBEntry(pitcher, {
        externalPlayerId: "pitcher-22",
        trigger: "strikeout_pitched",
        active: true,
        league: "mlb",
      })
    ).toBe(true);

    expect(
      matchesMLBEntry(batter, {
        externalPlayerId: "batter-11",
        trigger: "strikeout_batting",
        active: true,
        league: "mlb",
      })
    ).toBe(true);

    // Cross-role mismatch: pitcher sub's strikeout_pitched shouldn't match batter entry
    expect(
      matchesMLBEntry(batter, {
        externalPlayerId: "batter-11",
        trigger: "strikeout_pitched",
        active: true,
        league: "mlb",
      })
    ).toBe(false);
  });

  it("does NOT fire for non-MLB league subs", () => {
    const entries = parseMLBPlay(hrPlay());
    const batter = entries.find((e) => e.role === "batter")!;
    expect(
      matchesMLBEntry(batter, {
        externalPlayerId: "batter-42",
        trigger: "home_run",
        active: true,
        league: "nba",
      })
    ).toBe(false);
  });

  it("does NOT fire when externalPlayerId is null (unresolved MLB mapping)", () => {
    const entries = parseMLBPlay(hrPlay());
    const batter = entries.find((e) => e.role === "batter")!;
    expect(
      matchesMLBEntry(batter, {
        externalPlayerId: null,
        trigger: "home_run",
        active: true,
        league: "mlb",
      })
    ).toBe(false);
  });

  it("does NOT fire for inactive subscriptions", () => {
    const entries = parseMLBPlay(hrPlay());
    const batter = entries.find((e) => e.role === "batter")!;
    expect(
      matchesMLBEntry(batter, {
        externalPlayerId: "batter-42",
        trigger: "home_run_hit",
        active: false,
        league: "mlb",
      })
    ).toBe(false);
  });
});

// ---------- parsePlayByPlayResponse (MLB Stats API shape) ------------------

describe("parsePlayByPlayResponse", () => {
  it("converts a realistic MLB Stats API response into MLBPlay[] with batter + pitcher ids", () => {
    const raw = {
      allPlays: [
        {
          result: {
            type: "atBat",
            event: "Home Run",
            description:
              "Pete Alonso homers (28) on a fly ball to left center field.",
          },
          about: { inning: 3, halfInning: "top", atBatIndex: 12 },
          playEvents: [{ index: 0 }, { index: 1 }, { index: 2 }],
          matchup: { batter: { id: 624413 }, pitcher: { id: 660271 } },
          runners: [],
        },
        {
          result: {
            type: "atBat",
            event: "Strikeout",
            description: "McNeil strikes out swinging.",
          },
          about: { inning: 3, halfInning: "top", atBatIndex: 13 },
          playEvents: [{ index: 0 }],
          matchup: { batter: { id: 643446 }, pitcher: { id: 660271 } },
          runners: [],
        },
      ],
    };
    const plays = parsePlayByPlayResponse(raw, "gp-777");
    expect(plays).toHaveLength(2);

    const hr = plays[0];
    expect(hr.eventType).toBe("home_run");
    expect(hr.batterId).toBe("624413");
    expect(hr.pitcherId).toBe("660271");
    expect(hr.gameId).toBe("gp-777");
    expect(hr.halfInning).toBe("top");
    expect(hr.inning).toBe(3);
    // composite play id stitched from atBatIndex + last playEvent index
    expect(hr.playId).toBe("12.2");

    const k = plays[1];
    expect(k.eventType).toBe("strikeout");
    expect(k.batterId).toBe("643446");
  });

  it("surfaces stolen-base runner events as their own synthetic play", () => {
    const raw = {
      allPlays: [
        {
          result: {
            type: "atBat",
            event: "Walk",
            description: "Smith walks.",
          },
          about: { inning: 4, halfInning: "bottom", atBatIndex: 20 },
          playEvents: [{ index: 0 }],
          matchup: { batter: { id: 111 }, pitcher: { id: 222 } },
          runners: [
            {
              details: {
                runner: { id: 333 },
                event: "Stolen Base 2B",
              },
              movement: { start: "1B", end: "2B" },
            },
          ],
        },
      ],
    };
    const plays = parsePlayByPlayResponse(raw, "gp-1");
    // Expect the at-bat "walk" PLUS a synthetic stolen_base_2b row.
    const sb = plays.find((p) => p.eventType.startsWith("stolen_base"));
    expect(sb).toBeDefined();
    expect(sb!.runnerId).toBe("333");
    expect(sb!.halfInning).toBe("bottom");
  });

  it("gracefully returns [] for an empty allPlays payload", () => {
    expect(parsePlayByPlayResponse({ allPlays: [] }, "gp-1")).toEqual([]);
    expect(parsePlayByPlayResponse({}, "gp-1")).toEqual([]);
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
