# iOS app

This is a native SwiftUI + SwiftData application. Generate the Xcode project with `xcodegen generate` in this directory, then open `Ledgerly.xcodeproj`. It targets iOS 18 and adopts iOS 26 Liquid Glass automatically through availability-gated modifiers while retaining a material fallback.

Users choose the API and Convex URLs on the login screen. The simulator defaults are `http://localhost:3000` and `http://localhost:3210`; a physical phone needs reachable HTTPS endpoints. Opaque login sessions are stored in Keychain.

After signing in, Apple's Shortcuts app exposes **Add One-Time Bill** and **Add Recurring Bill** actions. Account choices are loaded from the configured Ledgerly server, and the session token remains in Ledgerly's Keychain rather than being copied into a Shortcut.

## Screenshot Sync

Open **Settings → Screenshot Sync**, choose the Ledgerly account that represents the banking or payment app, and enable automatic import. After taking a payment screenshot, return to Ledgerly: on-device Vision OCR reads the newest screenshot, creates a transaction, adjusts the selected balance, and queues the usual server sync. The Photos asset identifier is stored locally so the same screenshot is not imported twice.

Ledgerly requires full Photos access because iOS does not let an app continuously monitor another app or reliably discover the newest screenshot with limited access. OCR is performed on the iPhone and the image itself is never uploaded. iOS also prevents Ledgerly from running while the banking app is foregrounded, so import happens when Ledgerly becomes active rather than at the instant the screenshot is taken.

Run the unit tests with `xcodebuild test -scheme Ledgerly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
