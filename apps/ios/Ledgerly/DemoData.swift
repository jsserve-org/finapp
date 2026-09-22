#if DEBUG
import Foundation
import SwiftData

@MainActor
enum DemoData {
    static func load(into context: ModelContext) throws -> Bool {
        guard try context.fetchCount(FetchDescriptor<CachedAccount>()) == 0 else { return false }

        let checking = CachedAccount(name: "Daily checking", institution: "Cathay United Bank", kind: "checking", amountMinor: 82_450_00, currency: "TWD")
        let savings = CachedAccount(name: "Rainy day fund", institution: "Richart", kind: "savings", amountMinor: 240_000_00, currency: "TWD")
        let cash = CachedAccount(name: "EasyCard", institution: "EasyCard Corporation", kind: "cash", amountMinor: 860_00, currency: "TWD")
        [checking, savings, cash].forEach(context.insert)
        [checking, savings, cash].forEach { context.insert(PendingAccountMutation(entityId: $0.id)) }

        let calendar = Calendar.current
        let now = Date()
        let samples: [(CachedAccount, String, Int, Int, String, Bool)] = [
            (checking, "Monthly salary", 68_000_00, -2, "Income", false),
            (checking, "PX Mart", -1_248_00, -3, "Groceries", false),
            (checking, "Taiwan High Speed Rail", -1_490_00, -5, "Transport", false),
            (checking, "Louisa Coffee", -165_00, -6, "Dining", false),
            (checking, "Electricity bill", -1_840_00, -8, "Bills", false),
            (checking, "Uber", -320_00, 0, "Transport", true),
            (cash, "MRT top-up", -500_00, -9, "Transport", false)
        ]

        for (account, title, amount, dayOffset, category, pending) in samples {
            let date = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
            let timestamp = ISO8601DateFormatter().string(from: date)
            context.insert(CachedTransaction(dto: TransactionDTO(
                id: UUID().uuidString.lowercased(),
                accountId: account.id,
                description: title,
                amount: Money(amountMinor: amount, currency: "TWD"),
                bookedAt: timestamp,
                pending: pending,
                category: category,
                updatedAt: timestamp
            )))
        }

        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let recurring = [
            RecurringPayment(name: "Rent", amountMinor: 18_000_00, currency: "TWD", frequency: "monthly", nextDate: nextMonth, accountId: checking.id, category: "Housing"),
            RecurringPayment(name: "Chunghwa Telecom", amountMinor: 699_00, currency: "TWD", frequency: "monthly", nextDate: nextWeek, accountId: checking.id, category: "Bills"),
            RecurringPayment(name: "iCloud+", amountMinor: 90_00, currency: "TWD", frequency: "monthly", nextDate: nextWeek, accountId: checking.id, category: "Subscriptions")
        ]
        recurring.forEach {
            context.insert($0)
            context.insert(PendingRecurringMutation(entityId: $0.id, action: "upsert"))
        }

        try context.save()
        return true
    }
}
#endif
