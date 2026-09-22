# iOS app

This is a native SwiftUI + SwiftData application. Generate the Xcode project with `xcodegen generate` in this directory, then open `Ledgerly.xcodeproj`. It targets iOS 18 and adopts iOS 26 Liquid Glass automatically through availability-gated modifiers while retaining a material fallback.

For a physical phone, change `APIClient.baseURL` to the HTTPS address of your API. The simulator default is `http://localhost:3000`.
