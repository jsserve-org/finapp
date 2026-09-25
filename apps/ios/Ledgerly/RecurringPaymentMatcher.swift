import Foundation
import SwiftData

struct RecurringPaymentMatch {
    let payment: RecurringPayment
    let score: Int
    let shouldAutoLink: Bool
}

enum RecurringPaymentMatcher {
    static func compatiblePayments(for transaction: CachedTransaction, payments: [RecurringPayment]) -> [RecurringPayment] {
        compatiblePayments(currency: transaction.currency, accountID: transaction.accountId, payments: payments)
    }

    static func compatiblePayments(currency: String, accountID: String, payments: [RecurringPayment]) -> [RecurringPayment] {
        payments.filter {
            $0.isActive && $0.currency == currency && ($0.accountId == nil || $0.accountId == accountID)
        }
    }

    static func bestMatch(for transaction: CachedTransaction, payments: [RecurringPayment]) -> RecurringPaymentMatch? {
        bestMatch(
            title: transaction.title,
            amountMinor: transaction.amountMinor,
            currency: transaction.currency,
            accountID: transaction.accountId,
            category: transaction.category,
            payments: payments
        )
    }

    static func bestMatch(title: String, amountMinor: Int, currency: String, accountID: String, category: String?, payments: [RecurringPayment]) -> RecurringPaymentMatch? {
        let ranked = compatiblePayments(currency: currency, accountID: accountID, payments: payments)
            .map { payment in
                (payment, score(title: title, amountMinor: amountMinor, accountID: accountID, category: category, payment: payment))
            }
            .filter { $0.1 >= 4 }
            .sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        let margin = best.1 - (ranked.dropFirst().first?.1 ?? 0)
        return RecurringPaymentMatch(payment: best.0, score: best.1, shouldAutoLink: best.1 >= 7 && margin >= 2)
    }

    private static func score(title: String, amountMinor: Int, accountID: String, category: String?, payment: RecurringPayment) -> Int {
        var score = payment.accountId == accountID ? 2 : 1
        let transactionAmount = Double(amountMinor).magnitude
        let paymentAmount = Double(payment.amountMinor).magnitude
        let difference = abs(transactionAmount - paymentAmount)
        if difference == 0 { score += 4 }
        else if difference <= max(100, paymentAmount / 20) { score += 2 }

        let transactionWords = words(in: title)
        let paymentWords = words(in: payment.name)
        if !transactionWords.isDisjoint(with: paymentWords) { score += 4 }
        if let category,
           category.localizedCaseInsensitiveCompare(payment.category) == .orderedSame { score += 2 }
        return score
    }

    private static func words(in text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 3 })
    }
}

@MainActor
@discardableResult
func autoLinkRecurringPayment(_ transaction: CachedTransaction, payments: [RecurringPayment], context: ModelContext) -> Bool {
    guard transaction.amountMinor < 0,
          transaction.recurringPaymentId == nil,
          let match = RecurringPaymentMatcher.bestMatch(for: transaction, payments: payments),
          match.shouldAutoLink else { return false }
    transaction.recurringPaymentId = match.payment.id
    transaction.updatedAt = ISO8601DateFormatter().string(from: Date())
    enqueueFullTransaction(context: context, transactionID: transaction.id)
    return true
}
