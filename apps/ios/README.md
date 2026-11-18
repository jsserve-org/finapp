# iOS app

This is a native SwiftUI + SwiftData application. Generate the Xcode project with `xcodegen generate` in this directory, then open `Ledgerly.xcodeproj`. It targets iOS 18 and adopts iOS 26 Liquid Glass automatically through availability-gated modifiers while retaining a material fallback.

Users choose the API and Convex URLs on the login screen, and can update them later under Settings → Server. Saved endpoints persist across launches and are not replaced by server-advertised internal addresses. Build-time defaults come from `LEDGERLY_BASE_URL`; the development fallbacks are `http://localhost:3000` and `http://localhost:3210`. Opaque login sessions are stored in Keychain.

After signing in, Apple's Shortcuts app exposes **Add One-Time Bill** and **Add Recurring Bill** actions. Account choices are loaded from the configured Ledgerly server, and the session token remains in Ledgerly's Keychain rather than being copied into a Shortcut.

Settings → Screenshot Sync imports only a screenshot explicitly selected with Apple's photo picker; there is no background photo-library scanning. Transaction details can link any imported or regular payment to a compatible recurring bill. Settings → API Keys creates named, revocable keys for agents and automations, with the secret shown once.

## Screenshot Sync

Open **Settings → Screenshot Sync**, choose the Ledgerly account that represents the banking or payment app, then explicitly pick the screenshot you want to import. On-device Vision OCR reads that image, creates a transaction, adjusts the selected balance, and queues the usual server sync. The Photos asset identifier is stored locally so the same screenshot is not imported twice.

OCR is performed on the iPhone and the image itself is never uploaded. Ledgerly does not scan the photo library in the background.

Run the unit tests with `xcodebuild test -scheme Ledgerly -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`.

## Automatic subscription records

Active recurring bills with a selected account create pending expense records when due and advance to the next occurrence. These are expected payments: they do not change the cash balance. A matching recorded/imported payment links to the bill and replaces the nearby estimate. Ambiguous matches are left for manual linking.

Local-only mode catches up on launch, foregrounding, and once per minute while open. Synced accounts use the Convex scheduler every 15 minutes and catch up during sync; deploy the updated Convex functions and cron configuration to enable background generation. Schedules use Taiwan time, preserve month-end anchors, and process up to 36 missed occurrences per pass. Paused bills do not generate records.

Tap a bill in Activity to see all its linked transactions, including expected payments; Edit opens its schedule and pause/resume controls. Subscription history has no Activity date filter or 500-row cap.

## Holdings screenshots

In Investments, use the photo button to import a Taiwan stock holdings screenshot when the broker automation is unavailable. OCR runs on device. The importer uses table headers and text coordinates to pair stock names, quantities, average costs, and prices by row. Matched positions appear in a compact list, selected by default. Tap a row only when it needs correction, then use the single Import button for the selected positions. There are no per-stock confirmation switches. Covered or incomplete rows are grouped under Needs details and skipped until completed. Margin and short positions are kept out of cash-holdings imports. Alphanumeric ETF codes are preserved. OCR details are collapsed, and the original screenshot is available in the review form. The company-name picker uses the same public Taiwan exchange feeds as closing prices, with existing holdings available as a fallback; neither search terms nor screenshots are sent to the exchanges. Covered names require the user to choose the stock. A matching TWD position is updated rather than added; new positions use the TCStock importer's identity so a later automatic import replaces the snapshot. This queues a holding update for sync without creating trades or changing cash balances. Automatic imports may overwrite snapshots. Prices are daily closing quotes, not live intraday data; pull to refresh or choose Refresh from the Investments actions menu to update server positions and closing prices.

## Price history

Investments and each Taiwan stock detail page show an interactive daily-close line chart with a shaded area, 1W/1M/3M/6M/1Y ranges, and drag-to-inspect prices. The Investments chart lets you choose a stock from your open positions. History comes directly from TWSE and TPEx monthly daily-close tables, cached for 30 minutes. These are unadjusted stock prices, not total portfolio returns or intraday quotes. History requests send the selected public stock symbol and month to the exchange; they do not send quantities, screenshots, or account data. Hidden-amount mode hides the chart. Import, hide/show amounts, and Refresh share one actions menu; pull-to-refresh remains available.
