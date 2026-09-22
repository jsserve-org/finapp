# Ledgerly

An offline-first personal finance foundation with a Bun/TypeScript API, native SwiftUI iPhone app, and React Native Android app.

## Architecture

```text
iPhone (SwiftData) ─┐                       ┌─ bank provider adapter
                    ├─ HTTPS sync API ─ Postgres ─ automation worker
Android (SQLite) ───┘                       └─ health/self-check events
```

- `apps/api`: Bun + Hono + Drizzle/Postgres. Account and transaction reads, cursor-based sync, automation runs, readiness checks.
- `apps/ios`: SwiftUI/SwiftData shell targeting iOS 26. It uses system materials and availability-gated Liquid Glass APIs.
- `apps/android`: Expo/React Native Android shell with local SQLite storage.
- `packages/contracts`: shared TypeScript API types for the backend and Android client.

The API has `demo` bank automation for development. Real bank access belongs behind the same adapter via a regulated Open Banking provider; do not collect online-banking passwords in either app. Provider tokens should be envelope-encrypted by a cloud KMS before storage.

## Run the backend in Docker

The API, migration job, automation worker, and PostgreSQL all run in containers. Bun does not need to be installed on the host.

```sh
cp .env.example .env
docker compose up --build -d
docker compose ps
```

Compose runs the database migration once before starting `api` and `worker`. The API is published at `http://localhost:3000`; PostgreSQL remains private to the Docker network.

Useful commands:

```sh
docker compose logs -f api worker
docker compose down
```

For cloud deployments, build the same `Dockerfile` and run separate API, worker, and one-shot migration services. Set `API_DATABASE_URL` to the managed PostgreSQL connection string and use the platform's secret manager for `API_TOKEN` and provider credentials.

Check `http://localhost:3000/health/live` and use `Authorization: Bearer local-development-token` for `/v1/*` routes. Seed deterministic demo data with:

```sh
curl -X POST http://localhost:3000/v1/automations/demo/run \
  -H 'Authorization: Bearer local-development-token'
```

## Important production work

This repository is a secure architectural baseline, not a production banking integration. Before shipping: add OIDC/passkeys and per-user authorization, KMS-backed token encryption, a real provider consent flow, background job leases/retries, audit export/retention, observability, rate limiting, database backups, privacy/legal review, and App Store/Play policies. Never log provider credentials or raw access tokens.
