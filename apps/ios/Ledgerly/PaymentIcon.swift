import SwiftUI

enum PaymentIcon {
    static func symbol(title: String, category: String?, amountMinor: Int) -> String {
        if amountMinor > 0 { return "arrow.down.circle.fill" }
        let text = "\(category ?? "") \(title)".lowercased()
        let matches: [([String], String)] = [
            (["subscription", "netflix", "spotify", "icloud"], "play.rectangle.fill"),
            (["food", "dining", "restaurant", "coffee"], "fork.knife"),
            (["grocery", "supermarket"], "cart.fill"),
            (["housing", "rent", "mortgage"], "house.fill"),
            (["transport", "uber", "taxi", "fuel"], "car.fill"),
            (["shopping", "retail"], "bag.fill"),
            (["health", "medical", "pharmacy"], "cross.case.fill"),
            (["travel", "flight", "hotel"], "airplane"),
            (["education", "school"], "book.fill"),
            (["bill", "utility", "telecom"], "doc.text.fill"),
            (["screenshot", "import"], "photo.fill"),
        ]
        return matches.first(where: { words, _ in words.contains(where: text.contains) })?.1 ?? "creditcard.fill"
    }

    static func color(amountMinor: Int) -> Color {
        amountMinor >= 0 ? .green : .red
    }

    static func directionLabel(amountMinor: Int) -> String {
        amountMinor >= 0 ? "Received" : "Spent"
    }
}
