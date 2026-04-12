# Deep-Link Cold-Start QA

Push payload must include `subscriptionId` under `aps`-sibling key. Example payload saved at `/tmp/push.apns` used below:

```json
{ "aps": { "alert": { "title": "LeBron scored", "body": "35 pts" }, "sound": "default" }, "subscriptionId": "SUB_ID" }
```

Simulator device id assumed: `443E6045-BE5B-4339-B876-0C17BF2DFBA8`.

| # | Scenario | Steps | Expected |
|---|----------|-------|----------|
| 1 | Backgrounded | `xcrun simctl push <udid> app.statshot.StatShot /tmp/push.apns`, tap banner | Foregrounds on `AlertDetailView` for `SUB_ID` |
| 2 | Foregrounded | Same push command while app in front | Banner shows; tap opens `AlertDetailView` |
| 3 | Killed + signed in | `xcrun simctl terminate <udid> app.statshot.StatShot`, push, tap | Launches, lands on Alerts tab, detail sheet opens |
| 4 | Killed + signed out | Sign out in Settings, terminate, push, tap | Launches, auto-signs-in, then detail sheet opens |
| 5 | Killed + onboarding pending | `defaults write` to clear `hasSeenOnboarding` for the app, terminate, push, tap | Onboarding runs; on completion, Alerts tab opens detail sheet |
| 6 | Stale subscription | Delete sub in backend, push old id, tap | Toast: "This alert's subscription is no longer available." |

Run build: `cd ios && xcodegen generate && xcodebuild -project StatShot.xcodeproj -scheme StatShot -destination 'platform=iOS Simulator,id=443E6045-BE5B-4339-B876-0C17BF2DFBA8' -derivedDataPath build build`
