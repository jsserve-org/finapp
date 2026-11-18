# Ledgerly mobile

Shared Expo / React Native client with React Native Paper Material 3, wallpaper-derived Android colors, and a common Material Community Icons renderer. The original SwiftUI client is in `apps/ios`.

## Layout

The tab order follows the iOS app: **Insights → Accounts → Add → Activity → Settings**. The old Overview route redirects to Insights. Material navigation, typography, dialogs and colors remain native to the Paper theme.

Insights has grouped Summary, Spending by category (with a month menu), and Investments sections. Each currency is totaled separately, including synced holdings at their stored prices. Money in is green and money out is red, independent of the wallpaper accent. The eye action masks amounts across Insights, Accounts and Activity and remembers the setting locally.

The middle Add tab records transactions, opens New account, or opens New recurring payment. Recording a transaction updates the selected account's balance and queues both changes in one SQLite transaction; it does not initiate a payment. Account and recurring forms include a currency field. Local sync remains optional.

## Checks and builds

From this directory:

```sh
bun run typecheck
bun test src
bun run export
```

Native Android release builds use `android/gradlew assembleRelease` with the Android SDK and Java 17 configured. The sideloading release currently uses the existing debug signing key; keep that key to preserve update compatibility.

This layout update does not complete the full SwiftUI feature migration. The native iOS app still has additional stock-history, screenshot-import, subscription-detail, backup and privacy features. The shared app's Investments section currently summarizes synced holdings; it does not offer the native iOS stock detail or screenshot-import flow.
