import SwiftUI

/// Symbols available throughout Ledgerly's full iOS 18+ support range.
/// Keeping names here prevents a newer SF Symbol from silently rendering blank
/// on an older phone.
enum AppIcon {
    static let overview = "house.fill"
    static let accounts = "building.columns.fill"
    static let insights = "chart.bar.fill"
    static let activity = "list.bullet"
    static let settings = "gearshape.fill"
    static let account = "building.columns.fill"
    static let cash = "wallet.bifold.fill"
    static let recurring = "repeat"
    static let transaction = "arrow.up.arrow.down.circle.fill"
    static let empty = "tray.fill"
    static let synced = "checkmark.circle.fill"

    static func account(kind: String) -> String {
        switch kind {
        case "checking": "building.columns.fill"
        case "savings": "banknote.fill"
        case "credit", "sharedCredit": "creditcard.fill"
        case "investment": "chart.line.uptrend.xyaxis"
        case "cash": cash
        default: account
        }
    }
}

extension Image {
    func ledgerlyIcon(color: Color = .blue) -> some View {
        symbolRenderingMode(.monochrome)
            .fontWeight(.semibold)
            .foregroundStyle(color)
    }
}
