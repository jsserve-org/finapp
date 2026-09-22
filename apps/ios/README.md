# iOS app

This is a native SwiftUI + SwiftData application. Generate the Xcode project with `xcodegen generate` in this directory, then open `Ledgerly.xcodeproj`. It targets iOS 18 and adopts iOS 26 Liquid Glass automatically through availability-gated modifiers while retaining a material fallback.

Users choose the API and Convex URLs on the login screen. The simulator defaults are `http://localhost:3000` and `http://localhost:3210`; a physical phone needs reachable HTTPS endpoints. Opaque login sessions are stored in Keychain.

Run the unit tests with `xcodebuild test -scheme Ledgerly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
