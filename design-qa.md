# Mobile navigation design QA

- Source visual truth: `/Users/howard/.t3/userdata/attachments/e13cac63-6cc0-4a4b-b53f-5e53612c8e5b-d243652a-f973-4a91-a3c5-eb276e30b707.png`
- Implementation screenshot: `/tmp/ledgerly-navbar-overview-fixed.png`
- Side-by-side comparison: `/tmp/ledgerly-navbar-comparison.png`
- Device and viewport: iPhone 17 Pro simulator, 402 × 874 logical points at 3× density
- Source pixels: 1179 × 2556
- Implementation pixels: 1206 × 2622
- Normalization: both full-screen captures were proportionally resized to 1278 px high for the side-by-side comparison; device chrome was retained in both.
- State: Overview selected, empty local cache, offline sync banner visible

## Full-view comparison evidence

The implementation keeps a persistent five-item bottom navigation in the same information pattern as the references: overview, accounts, analysis/insights, activity/details, and profile/settings. The active destination uses the product accent color and a filled/high-emphasis icon treatment; inactive destinations remain quieter. The bar clears the home indicator and the scroll content remains visible above it.

The reference app's light cyan/orange visual language and Chinese copy were treated as navigation-pattern inspiration rather than a full-screen reskin. Ledgerly's existing dark green palette, English product vocabulary, data cards, and native iOS 26 tab-bar material were intentionally preserved.

## Focused region comparison evidence

The bottom navigation region was inspected at native simulator resolution. All five icon/label pairs are readable without truncation, the selected Overview item has a distinct mint background and foreground, and the bar has sufficient separation from content and device chrome. No additional crop was needed because the full-resolution captures make all tab labels and icons legible.

## Required fidelity surfaces

- Fonts and typography: native San Francisco typography is consistent with the existing SwiftUI app; tab labels use the system optical sizing and do not wrap or truncate.
- Spacing and layout rhythm: five destinations fit evenly, the bar respects the bottom safe area, and scrollable content is not hidden underneath it.
- Colors and visual tokens: the navbar reuses Ledgerly mint, deep green, and secondary gray rather than introducing the reference app's unrelated brand colors.
- Image and icon quality: all navigation icons are native SF Symbols (and Ionicons in Expo), rendered as vectors at device density; no placeholder or hand-drawn assets are used.
- Copy and content: labels are short, recognizable, and consistent across iOS and Expo: Overview, Accounts, Insights, Activity, and Settings.

## Interaction and runtime checks

- Confirmed Overview → Accounts → Insights → Activity → Settings through the iOS Simulator accessibility tree.
- Confirmed the app launches full-screen after adding `UILaunchScreen`; the earlier letterboxed presentation is fixed.
- Native app launched without a crash. No browser console applies to this SwiftUI build.
- The visible offline JSON decoding message comes from the existing local API response and is outside the navbar change.
- Expo route modules passed a Bun JSX/TypeScript syntax build. Full Expo typechecking is unavailable in this checkout because dependencies are not installed and the installed Bun 1.3.6 cannot read the repository's Bun 1.4 lockfile.

## Comparison history

1. P1: the initial simulator capture was letterboxed because the app had no launch-screen declaration, compressing the app and crowding the tab bar. Added an empty native `UILaunchScreen` declaration to `Info.plist` and `project.yml`.
2. Post-fix evidence: `/tmp/ledgerly-navbar-overview-fixed.png` shows the app filling the iPhone 17 Pro display with the navbar correctly placed above the home indicator.

## Findings

No actionable P0, P1, or P2 navbar issues remain.

## Follow-up polish

- P3: add notification badges only when Ledgerly has a real unread or action-required count; the reference badge should not be copied without corresponding product data.

final result: passed
