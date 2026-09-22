# iOS app

This is a native SwiftUI + SwiftData application. Generate the Xcode project with `xcodegen generate` in this directory, then open `Ledgerly.xcodeproj`. It targets iOS 18 and adopts iOS 26 Liquid Glass automatically through availability-gated modifiers while retaining a material fallback.

The base URL and bearer token come from the build settings `LEDGERLY_BASE_URL` and `LEDGERLY_API_TOKEN` (defaults in `project.yml`; the simulator default is `http://localhost:3000`). For a physical phone, set `LEDGERLY_BASE_URL` to the HTTPS address of your API. You can also store a token in the Keychain from the in-app Settings screen, which takes precedence over the build-config value.

Run the unit tests with `xcodebuild test -scheme Ledgerly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.
