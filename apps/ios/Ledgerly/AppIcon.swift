import SwiftUI

/// Symbols available throughout Ledgerly's full iOS 18+ support range.
/// Keeping names here prevents a newer SF Symbol from silently rendering blank
/// on an older phone.
enum AppIcon {
    static let overview = "house.fill"
    static let accounts = "creditcard.fill"
    static let insights = "chart.bar.fill"
    static let activity = "list.bullet"
    static let settings = "gearshape.fill"
    static let account = "building.columns.fill"
    static let cash = "dollarsign.circle.fill"
    static let recurring = "repeat"
    static let transaction = "arrow.up.arrow.down.circle.fill"
    static let empty = "tray.fill"
    static let synced = "checkmark.circle.fill"
}

extension Image {
    func ledgerlyIcon(color: Color = .blue) -> some View {
        symbolRenderingMode(.monochrome)
            .fontWeight(.semibold)
            .foregroundStyle(color)
    }
}
