# Ledgerly

An offline-first finance app with native SwiftUI iOS, React Native Android, a Bun authentication/bank gateway, and a self-hosted Convex sync layer.

Both apps can be used without a server account. Users can continue locally, create manual accounts immediately, and enable self-hosted sync later from Settings. Local account data is stored in SwiftData on iOS and SQLite on Android; an outbox uploads locally created accounts after the user opts into sync.

## Services

```text
iOS / Android ─┬─ HTTPS :3000  Bun API (login and bank integrations)
               └─ WSS   :3210  Convex (realtime sync)
                                  └─ persistent convex-data volume
Admin only ────── HTTPS :6791  Convex dashboard
```

Postgres and Drizzle have been removed. Convex now owns users, opaque sessions, accounts, transactions, sync changes, mutation deduplication, and automation status. Passwords are processed by the Bun gateway with Argon2id; Convex stores only the resulting salted hash. Mobile devices store only an opaque session token in Keychain/SecureStore, together with the server-issued API URL, Convex URL, sync-session ID, and local sync cursor.

## First-time Docker setup

```sh
cp .env.example .env
# Replace both placeholder secrets in .env first.
docker compose up -d convex dashboard
docker compose exec convex ./generate_admin_key.sh
```

Copy the generated key into `CONVEX_SELF_HOSTED_ADMIN_KEY` in `.env`, then deploy the checked-in schema and functions:

```sh
docker compose --profile tools run --rm convex-deploy
docker compose up --build -d api
curl http://localhost:3000/health/ready
```

The login screens let users set both endpoints. Emulator defaults are `http://10.0.2.2:3000` and `http://10.0.2.2:3210`; the iOS Simulator uses `localhost`. Administrators can set `ALLOW_REGISTRATION=false` and restart the API after creating users. The API then rejects registration with HTTP 403 and `/v1/config` tells both apps to hide the registration option.

## Opening ports

For a private LAN test, replace `localhost` in the three `PUBLIC_*` values with the server's LAN IP, then allow only trusted LAN clients:

```sh
# Ubuntu UFW example; replace 192.168.1.0/24 with your actual subnet.
sudo ufw allow from 192.168.1.0/24 to any port 3000 proto tcp
sudo ufw allow from 192.168.1.0/24 to any port 3210 proto tcp
```

Do not expose ports 3000, 3210, 3211, or 6791 directly to the public internet. Put the API and Convex backend behind a TLS reverse proxy and expose only TCP 443. Route distinct public hostnames, for example:

- `https://api.finance.example` → `api:3000`
- `https://sync.finance.example` → `convex:3210` (WebSocket upgrades required)
- `https://actions.finance.example` → `convex:3211`, only if HTTP actions are added
- Keep the dashboard (`6791`) private behind VPN/SSH tunneling and authentication.

Set `PUBLIC_API_URL` and `PUBLIC_CONVEX_URL` to those HTTPS URLs. Mobile login rejects a Convex endpoint that does not match the API's configured public deployment. Configure DNS, a valid certificate, rate limiting, backups for `convex-data`, and pinned Convex image versions before production.

## Authentication behavior

Registration and login passwords are sent only to the chosen API endpoint. Production therefore requires HTTPS. The server performs Argon2id hashing and never stores the plaintext password or password-derived value in a session. Successful login creates a random 256-bit opaque token; Convex stores only its SHA-256 digest. Sessions expire after 30 days and can be revoked at logout.

Client-side-only hashing is deliberately not used because that hash becomes a replayable password equivalent. If proof-based password authentication is needed later, implement OPAQUE or WebAuthn/passkeys rather than inventing a custom challenge protocol.

## Development and verification

```sh
bun install
bun typecheck
bun test
docker compose logs -f api convex
```

The demo automation remains available after login at `POST /v1/automations/demo/run`. Real bank access belongs behind a regulated Open Banking provider and requires encrypted provider tokens, audit logs, rate limiting, and privacy review.

See [BILL_API.md](BILL_API.md) for the authenticated one-time and recurring bill API intended for AI agents and mobile automation. The iOS app also publishes matching actions to Apple's Shortcuts app.
