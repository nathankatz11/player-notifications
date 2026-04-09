# StatShot — Sports Alert App

## Quick Reference
- **Platform**: iOS 17+ (Swift 6 / SwiftUI)
- **Backend**: Next.js on Vercel (TypeScript)
- **Database**: Neon Postgres via Vercel Marketplace (Drizzle ORM)
- **Auth**: Sign in with Apple → Vercel API
- **Push**: Direct APNs (HTTP/2 from Vercel Functions)
- **Data Source**: ESPN unofficial API
- **Payments**: Stripe (premium tier)
- **SMS**: Twilio (premium tier)

## Project Structure
```
player-notifications/
├── ios/                          # iOS app
│   ├── project.yml               # XcodeGen project definition
│   └── StatShot/                 # SwiftUI app source
│       ├── App/                  # Entry point
│       ├── Models/               # Data models
│       ├── Views/                # SwiftUI views
│       ├── ViewModels/           # @Observable view models
│       └── Services/             # APIService, Auth, Notifications, Stripe
├── backend/                      # Next.js Vercel backend
│   ├── app/api/                  # API routes
│   │   ├── register/             # POST — device registration
│   │   ├── scores/               # GET — live scores (all + per league)
│   │   ├── search/               # GET — player/team search
│   │   ├── subscriptions/        # GET/POST/PUT/DELETE — alert subscriptions
│   │   ├── alerts/               # GET — alert history
│   │   └── cron/poll/            # GET — Vercel Cron (ESPN polling)
│   ├── lib/
│   │   ├── db/                   # Neon Postgres + Drizzle schema
│   │   ├── espn.ts               # ESPN API client
│   │   ├── apns.ts               # APNs push client
│   │   ├── twilio.ts             # Twilio SMS client
│   │   └── alerts.ts             # Alert matching engine
│   ├── drizzle.config.ts         # Drizzle Kit config
│   └── vercel.json               # Cron job config
└── SKILL.md                      # Full product spec (Justin's)
```

## iOS Coding Standards
- Use `@Observable` (not `ObservableObject`)
- Use `async/await` for all async operations
- Use `NavigationStack` (not `NavigationView`)
- Use `@Environment` for dependency injection
- Extract views when they exceed 100 lines
- Swift 6 strict concurrency

## Backend Conventions
- Next.js App Router with route handlers
- Neon Postgres via `@neondatabase/serverless` + Drizzle ORM
- Lazy DB initialization (proxy pattern) for build-time safety
- Vercel Cron runs `/api/cron/poll` every minute
- CRON_SECRET header validation on cron endpoint

## Build Commands
- Backend: `cd backend && npm run build`
- Backend dev: `cd backend && npm run dev`
- iOS: Generate Xcode project with `cd ios && xcodegen generate`
- DB migrations: `cd backend && npx drizzle-kit push`

## Spec
@import SKILL.md
