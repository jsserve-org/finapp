# iOS agent handoff

The iOS client is a native SwiftUI/SwiftData app in `apps/ios/Ledgerly`. The backend and worker run through root-level Docker Compose.

## Current implementation

- Dashboard with account balances, recent transactions, offline banner, and pending-edit counter.
- SwiftData cache (`CachedAccount`, `CachedTransaction`, `SyncSetting`) for offline launch.
- Cursor-based calls to `POST /v1/sync` via the `@MainActor` `SyncEngine`, which also drains a `PendingMutation` outbox (offline edits/deletes queue locally, flush on next sync, deduped by `mutationId`).
- Transaction detail with edit/delete (outbox-backed), account detail with filtered history, connection-health screen (`GET /v1/automations/status` + demo import), and settings screen (Keychain token management, API health check).
- Keychain-backed bearer token (`KeychainStore`) with build-config fallback.
- Users choose the API and Convex URLs at login. The opaque session token is stored in Keychain; use HTTPS on a physical device.
- Stock SwiftUI navigation, forms, lists, toolbars, and tab bar. iOS 26 supplies its native Liquid Glass treatment automatically, while earlier supported versions retain their system appearance.
- App Intents for creating one-time and recurring bills through Apple Shortcuts; both use the authenticated bill API and server-backed account picker.
- Screenshot Sync imports the newest payment screenshot into a user-selected account when Ledgerly becomes active. Vision OCR remains on-device, Photos assets are deduplicated by local identifier, and only the resulting transaction enters the normal sync outbox.
- Account deletion cascades to linked transactions and recurring bills locally and through the sync server.
- An AppIcon asset catalog plus an iOS 18-safe SF Symbol catalog for visible icons throughout the supported OS range.
- Unit test target `LedgerlyTests` (17 tests): DTO decoding against the API's JSON shape, `JSONValue` ordering, cache upsert/merge/delete, cursor persistence, outbox operation encoding, backup restoration, and Screenshot Sync payment parsing.
- XcodeGen specification in `project.yml`.

## Build & test

```sh
cd apps/ios
xcodegen generate
xcodebuild -project Ledgerly.xcodeproj -scheme Ledgerly \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Ledgerly.xcodeproj -scheme Ledgerly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Suggested next-agent scope

1. Add UI tests for offline launch and pull-to-refresh behavior.
2. Validate the stock iOS 26 Liquid Glass tab bar against accessibility settings (Reduced Motion/Transparency).
3. Replace the development identity bearer token with OIDC once the API grows real auth.
4. Consider background refresh (`BGTaskScheduler`) and pull-based pagination if change feeds exceed 500 entries.

## Local backend

From the repository root:

```sh
cp .env.example .env
docker compose up --build -d
curl http://localhost:3000/health/ready
curl -X POST http://localhost:3000/v1/automations/demo/run \
  -H 'Authorization: Bearer local-development-token'
```

The iOS Simulator can reach `http://localhost:3000` (set via `LEDGERLY_BASE_URL`). A physical iPhone needs a reachable HTTPS hostname and a matching base URL. If port 3000 is occupied by another dev server, start the stack with `API_PORT=3100 docker compose up --build -d` and change `LEDGERLY_BASE_URL` in `project.yml` to match.
