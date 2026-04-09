# SKILL.md — StatShot Sports Alert App

## Project Overview
StatShot is an iOS app that sends real-time push notifications (free) and SMS alerts (premium) when specific sports events occur — e.g., "Notify me every time Russell Westbrook turns the ball over" or "Text me when the Gators win." Users subscribe to granular player/team/stat combinations across all major sports leagues.

## Target Users
- **Casual fans** — team win/loss alerts
- **Degen sports fans** — obsessive stat tracking (every turnover, every goal, every ejection)
- **Bettors** — real-time in-game alerts for prop bet monitoring

---

## Tech Stack

| Layer | Tool | Notes |
|---|---|---|
| Mobile | Swift (iOS native) | SwiftUI for UI, Combine for reactive state |
| Backend | Firebase Cloud Functions (Node.js) | Polling + alert dispatch |
| Database | Firestore | Users, subscriptions, alert history |
| Auth | Firebase Auth | Email/password + Sign in with Apple |
| Push Notifications | Firebase Cloud Messaging (FCM) | Free, via APNs |
| SMS | Twilio | Premium tier only |
| Sports Data | ESPN API + TheSportsDB | Free — see API section below |
| Payments | Stripe | Freemium gating |
| Scheduler | Firebase Cloud Scheduler | Triggers polling functions |

---

## Free Sports Data APIs

### Primary: ESPN API (Unofficial, Free)
- No API key required
- Base URL: `https://site.api.espn.com/apis/site/v2/sports/`
- Endpoints:
  - NBA: `/basketball/nba/scoreboard`
  - NFL: `/football/nfl/scoreboard`
  - NHL: `/hockey/nhl/scoreboard`
  - MLB: `/baseball/mlb/scoreboard`
  - College Football: `/football/college-football/scoreboard`
  - College Basketball: `/basketball/mens-college-basketball/scoreboard`
  - MLS: `/soccer/usa.1/scoreboard`
- Play-by-play: `https://site.api.espn.com/apis/site/v2/sports/{sport}/{league}/summary?event={game_id}`
- **Polling interval:** Every 15–20 seconds during live games

### Secondary: TheSportsDB (Free tier)
- URL: `https://www.thesportsdb.com/api/v1/json/3/`
- Use for: team/player metadata, logos, historical data
- Free tier: 1 API key, rate limited

### Fallback: MySportsFeeds (paid but cheap)
- Only if ESPN gaps are too large
- $1/month developer tier covers low volume

---

## Firestore Schema

```
/users/{userId}
  - email: string
  - phone: string | null
  - fcmToken: string
  - plan: "free" | "premium"
  - createdAt: timestamp

/subscriptions/{subscriptionId}
  - userId: string
  - type: "player_stat" | "team_event"
  - league: "nba" | "nfl" | "nhl" | "mlb" | "ncaafb" | "ncaamb" | "mls"
  - entityId: string          // ESPN player ID or team ID
  - entityName: string        // "Russell Westbrook", "Florida Gators"
  - trigger: string           // "turnover" | "goal" | "win" | "touchdown" | "ejection"
  - deliveryMethod: "push" | "sms" | "both"
  - active: boolean
  - createdAt: timestamp

/alerts/{alertId}
  - subscriptionId: string
  - userId: string
  - message: string
  - sentAt: timestamp
  - deliveryMethod: "push" | "sms"
  - gameId: string
  - eventDescription: string

/games/{gameId}
  - league: string
  - homeTeam: string
  - awayTeam: string
  - status: "pre" | "in" | "post"
  - lastPolledAt: timestamp
  - lastPlayId: string        // track last processed play to avoid duplicates
```

---

## Cloud Functions Architecture

### 1. `pollLiveGames` (Scheduled — every 15 seconds during game hours)
```
- Fetch scoreboard for each active league
- Identify games with status = "in"
- For each live game, fetch play-by-play summary
- Compare lastPlayId in Firestore to detect new plays
- For each new play, call matchAndAlert()
```

### 2. `matchAndAlert(play, gameId)`
```
- Parse play for: player involved, stat type, team
- Query subscriptions where entityId matches AND trigger matches
- For each matching subscription:
  - If deliveryMethod = "push" → sendFCM()
  - If deliveryMethod = "sms" → sendTwilioSMS() [premium only]
  - Write to /alerts collection
```

### 3. `sendFCM(userId, message)`
```
- Fetch user FCmToken from Firestore
- Send via Firebase Admin SDK
- Free, no limits at reasonable scale
```

### 4. `sendTwilioSMS(userId, message)`
```
- Fetch user phone from Firestore
- Verify user.plan === "premium" before sending
- Send via Twilio REST API
- Log to /alerts
```

### 5. `searchEntity` (HTTP — called from app)
```
- Accepts: query string, league
- Hits ESPN search endpoint
- Returns: [{id, name, type, league, imageUrl}]
- Used for the subscription setup flow in app
```

### 6. `manageSubscription` (HTTP — called from app)
```
- Create / update / delete subscriptions
- Enforce free tier limit (3 subscriptions max)
- Validate Stripe subscription status for premium
```

---

## iOS App Structure (SwiftUI)

```
StatShot/
├── App/
│   └── StatShotApp.swift
├── Views/
│   ├── HomeView.swift           // Active subscriptions list
│   ├── AddAlertView.swift       // Search + configure new alert
│   ├── AlertHistoryView.swift   // Log of fired alerts
│   ├── SettingsView.swift       // Account, notifications, SMS
│   └── PaywallView.swift        // Stripe upgrade flow
├── ViewModels/
│   ├── SubscriptionViewModel.swift
│   ├── AlertHistoryViewModel.swift
│   └── AuthViewModel.swift
├── Services/
│   ├── FirebaseService.swift    // Firestore CRUD
│   ├── AuthService.swift        // Firebase Auth
│   ├── NotificationService.swift // FCM + APNs registration
│   └── StripeService.swift      // Paywall
├── Models/
│   ├── Subscription.swift
│   ├── Alert.swift
│   └── User.swift
└── Config/
    └── GoogleService-Info.plist
```

---

## Trigger Types by League

### NBA
- `points_scored` — player scores
- `turnover` — player turns ball over
- `technical_foul` — player gets T'd up
- `ejection`
- `game_winner`
- `team_win` / `team_loss`

### NFL
- `touchdown` — player scores TD
- `interception` — QB throws INT
- `fumble`
- `sack`
- `field_goal`
- `team_win` / `team_loss`

### NHL
- `goal` — player scores
- `assist`
- `penalty`
- `hat_trick`
- `shutout`
- `team_win` / `team_loss`

### MLB
- `home_run`
- `strikeout` (pitcher or batter)
- `stolen_base`
- `error`
- `team_win` / `team_loss`

### College Football / Basketball
- `touchdown`, `field_goal`, `team_win`, `team_loss`
- `points_scored`, `team_win`, `team_loss`

### MLS / Soccer
- `goal`
- `red_card`
- `penalty_kick`
- `team_win` / `team_loss`

---

## Freemium Model

| Feature | Free | Premium ($4.99/mo) |
|---|---|---|
| Active alerts | 3 max | Unlimited |
| Delivery | Push only | Push + SMS |
| Sports | All | All |
| Alert granularity | All triggers | All triggers |
| Alert history | 7 days | 90 days |
| SMS to another number | ❌ | ✅ |

---

## Alert Message Format

Keep messages punchy and specific:

- `🏀 TURNOVER — Russell Westbrook just coughed it up. LAL 88, GSW 91 | Q3 4:22`
- `🏒 GOAL — Ovechkin scores his 37th of the season. WSH 3, NYR 1 | 2nd Period`
- `🏈 WIN — Your Gators beat Tennessee 34-20. Final.`
- `⚾ HOME RUN — Aaron Judge crushes #42. NYY 4, BOS 2 | Bot 6`

---

## Known Risks

1. **ESPN API stability** — Unofficial API, no SLA. If it goes down, polling fails silently. Add error logging and fallback to TheSportsDB.
2. **15-second polling cost** — Firebase Cloud Functions free tier = 2M invocations/month. At 15s intervals across 7 leagues = ~40K invocations/day. Well within free tier during MVP.
3. **Play-by-play parsing inconsistency** — ESPN formats vary by sport. Build a parser per league, don't try to generalize.
4. **Duplicate alerts** — Always check lastPlayId before firing. Store fired alertIds in Firestore to prevent double-sends.
5. **App Store review** — Notification-heavy apps sometimes get scrutinized. Frame as "personalized sports alerts," not a gambling tool.
6. **Twilio cost at scale** — $0.0079/SMS. 10K SMS/month = $79. Gate hard behind Stripe before scaling.
