# iOS app

This is a native SwiftUI + SwiftData application. Generate the Xcode project with `xcodegen generate` in this directory, then open `Ledgerly.xcodeproj`. It targets iOS 18 and adopts iOS 26 Liquid Glass automatically through availability-gated modifiers while retaining a material fallback.

Users choose the API and Convex URLs on the login screen, and can update them later under Settings → Server. Saved endpoints persist across launches and are not replaced by server-advertised internal addresses. Build-time defaults come from `LEDGERLY_BASE_URL`; the development fallbacks are `http://localhost:3000` and `http://localhost:3210`. Opaque login sessions are stored in Keychain.

After signing in, Apple's Shortcuts app exposes **Add One-Time Bill** and **Add Recurring Bill** actions. Account choices are loaded from the configured Ledgerly server, and the session token remains in Ledgerly's Keychain rather than being copied into a Shortcut.

Settings → Screenshot Sync imports only a screenshot explicitly selected with Apple's photo picker; there is no background photo-library scanning. Transaction details can link any imported or regular payment to a compatible recurring bill. Settings → API Keys creates named, revocable keys for agents and automations, with the secret shown once.

## Screenshot Sync

Open **Settings → Screenshot Sync**, choose the Ledgerly account that represents the banking or payment app, then explicitly pick the screenshot you want to import. On-device Vision OCR reads that image, creates a transaction, adjusts the selected balance, and queues the usual server sync. The Photos asset identifier is stored locally so the same screenshot is not imported twice.

OCR is performed on the iPhone and the image itself is never uploaded. Ledgerly does not scan the photo library in the background.

Run the unit tests with `xcodebuild test -scheme Ledgerly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

## Automatic subscription records

Active recurring bills with a selected account create pending expense records when due and advance to the next occurrence. These are expected payments: they do not change the cash balance. A matching recorded/imported payment links to the bill and replaces the nearby estimate. Ambiguous matches are left for manual linking.

Local-only mode catches up on launch, foregrounding, and once per minute while open. Synced accounts use the Convex scheduler every 15 minutes and catch up during sync; deploy the updated Convex functions and cron configuration to enable background generation. Schedules use Taiwan time, preserve month-end anchors, and process up to 36 missed occurrences per pass. Paused bills do not generate records.

Tap a bill in Activity to see all its linked transactions, including expected payments; Edit opens its schedule and pause/resume controls. Subscription history has no Activity date filter or 500-row cap.
