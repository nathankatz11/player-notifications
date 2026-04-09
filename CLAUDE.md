# StatShot — Sports Alert App

## Quick Reference
- **Platform**: iOS 17+ (Swift 6 / SwiftUI)
- **Backend**: Firebase Cloud Functions (TypeScript)
- **Database**: Firestore
- **Auth**: Firebase Auth (Sign in with Apple)
- **Push**: FCM → APNs
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
│       └── Services/             # Firebase, Auth, Notifications, Stripe
├── functions/                    # Firebase Cloud Functions
│   └── src/
│       ├── polling/              # ESPN score polling
│       ├── alerts/               # Alert matching + dispatch (FCM, Twilio)
│       ├── api/                  # HTTP endpoints (search, subscriptions)
│       └── lib/                  # ESPN client, types
├── firebase.json                 # Firebase config
├── firestore.rules               # Security rules
├── firestore.indexes.json        # Firestore indexes
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
- Firebase Functions v2 API (`firebase-functions/v2/*`)
- TypeScript strict mode
- ESPN polling runs every 1 minute via Cloud Scheduler
- Alert deduplication via `lastPlayId` in Firestore `/games/{id}`

## Build Commands
- Backend: `cd functions && npm run build`
- Backend dev: `firebase emulators:start`
- iOS: Generate Xcode project with `cd ios && xcodegen generate`

## Spec
@import SKILL.md
