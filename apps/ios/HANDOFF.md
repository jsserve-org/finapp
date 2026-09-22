# iOS agent handoff

The iOS client is a native SwiftUI/SwiftData starting point in `apps/ios/Ledgerly`. The backend and worker run through root-level Docker Compose.

## Current implementation

- Dashboard with account balances and recent transactions.
- SwiftData cache for offline launch.
- Cursor-based calls to `POST /v1/sync`.
- iOS 26 Liquid Glass via an availability-gated modifier, with an iOS 18 material fallback.
- XcodeGen specification in `project.yml`.

## Suggested next-agent scope

1. On macOS, install XcodeGen and run `xcodegen generate` from `apps/ios`.
2. Compile with current Xcode/iOS SDK and fix any Swift 6 concurrency or SwiftData predicate issues.
3. Move the base URL and development token into build configurations; use HTTPS for a physical device.
4. Add Keychain-backed authentication, account detail, transaction detail/editing, sync mutation outbox, and connection-health screens.
5. Add unit tests for decoding/cache application and UI tests for offline and refresh behavior.
6. Validate Liquid Glass against Apple's current iOS 26 API and accessibility settings.

## Local backend

From the repository root:

```sh
cp .env.example .env
docker compose up --build -d
curl http://localhost:3000/health/ready
curl -X POST http://localhost:3000/v1/automations/demo/run \
  -H 'Authorization: Bearer local-development-token'
```

The iOS Simulator can reach `http://localhost:3000`. A physical iPhone needs a reachable HTTPS hostname and a matching base URL in `APIClient.swift`.
