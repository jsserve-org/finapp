# iOS agent handoff

The iOS client is a native SwiftUI/SwiftData app in `apps/ios/Ledgerly`. The backend and worker run through root-level Docker Compose.

## Current implementation

- Dashboard with account balances, recent transactions, offline banner, and pending-edit counter.
- SwiftData cache (`CachedAccount`, `CachedTransaction`, `SyncSetting`) for offline launch.
- Cursor-based calls to `POST /v1/sync` via the `@MainActor` `SyncEngine`, which also drains a `PendingMutation` outbox (offline edits/deletes queue locally, flush on next sync, deduped by `mutationId`).
- Transaction detail with edit/delete (outbox-backed), account detail with filtered history, connection-health screen (`GET /v1/automations/status` + demo import), and settings screen (Keychain token management, API health check).
- Keychain-backed bearer token (`KeychainStore`) with build-config fallback.
- Base URL and token come from build settings `LEDGERLY_BASE_URL` / `LEDGERLY_API_TOKEN` (see `project.yml`), read through `AppConfig.swift`. Use HTTPS for a physical device.
- iOS 26 Liquid Glass via the availability-gated `ledgerlyGlass` modifier, with an iOS 18 material fallback.
- Unit test target `LedgerlyTests` (11 tests): DTO decoding against the API's JSON shape, `JSONValue` ordering, cache upsert/merge/delete, cursor persistence, outbox operation encoding.
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
2. Validate Liquid Glass against Apple's current iOS 26 API and accessibility settings (Reduced Motion/Transparency).
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
