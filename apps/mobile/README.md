# Ledgerly mobile (Expo)

One Expo (SDK 54 + expo-router) app for iPhone and Android. It replaces the two
separate clients: the native SwiftUI app in `apps/ios` (kept as a reference while
parity is verified) and the old `apps/android` skeleton.

## The same behaviour as the SwiftUI app

- Local-first SQLite cache (`expo-sqlite`) with the same entity shapes the API
  syncs: accounts, transactions, recurring bills, stock holdings and trades.
- Offline outbox that coalesces edits per entity and drains through
  `POST /v1/sync` with protocol version 2, including the 500-change pagination
  loop and the server compatibility check.
- Balance rules ported from `AccountActions.swift`: manual money in/out, bank
  settlement pending when the purchase currency differs, transfers written as a
  matched pair, deletions that reverse their balance impact, and bill estimates.
- Keychain/Keystore session storage, server + Convex endpoints chosen at login,
  "continue on this iPhone" local-only mode, API key management.

## iOS look and feel

- `NativeTabs` gives the real iOS tab bar, including the iOS 26 Liquid Glass
  treatment, with an `SF Symbols` icon set (`expo-symbols`).
- `expo-glass-effect` renders `GlassView` surfaces for the summary and detail
  cards when Liquid Glass is available, and falls back to the grouped-card
  material used by earlier iOS versions.
- Native stack headers (large titles, sheet modals, search bar), grouped inset
  lists, iOS system colours, haptics, and a floating glass Add button that opens
  the same native action sheet as the SwiftUI tab menu.

## Commands

```sh
bun install
bunx expo start            # dev server
bun run typecheck
bun test                   # SQLite cache + sync tests
bunx expo export --platform ios      # bundle sanity check
```

## Build and share with AppDrop

```sh
./scripts/build-ipa.sh                  # runs prebuild + xcodebuild, writes ios/build/Ledgerly-v<version>.ipa
npx appdrop ios/build/Ledgerly-v0.6.20.ipa
```

The script produces an unsigned/ad-hoc IPA; AppDrop re-signs it for the Apple ID
of whoever installs from the link. Android builds can be shared as an `.apk`
or `.aab` the same way (`npx appdrop build/app-release.apk`).
