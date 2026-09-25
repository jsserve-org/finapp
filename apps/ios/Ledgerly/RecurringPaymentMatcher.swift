import Foundation
import SwiftData

struct RecurringPaymentMatch {
    let payment: RecurringPayment
    let score: Int
    let shouldAutoLink: Bool
}

enum RecurringPaymentMatcher {
    static func compatiblePayments(for transaction: CachedTransaction, payments: [RecurringPayment]) -> [RecurringPayment] {
        payments.filter {
            $0.isActive && $0.currency == transaction.currency && ($0.accountId == nil || $0.accountId == transaction.accountId)
        }
    }

    static func bestMatch(for transaction: CachedTransaction, payments: [RecurringPayment]) -> RecurringPaymentMatch? {
        let ranked = compatiblePayments(for: transaction, payments: payments)
            .map { payment in (payment, score(transaction: transaction, payment: payment)) }
            .filter { $0.1 >= 4 }
            .sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        let margin = best.1 - (ranked.dropFirst().first?.1 ?? 0)
        return RecurringPaymentMatch(payment: best.0, score: best.1, shouldAutoLink: best.1 >= 7 && margin >= 2)
    }

    private static func score(transaction: CachedTransaction, payment: RecurringPayment) -> Int {
        var score = payment.accountId == transaction.accountId ? 2 : 1
        let transactionAmount = Double(transaction.amountMinor).magnitude
        let paymentAmount = Double(payment.amountMinor).magnitude
        let difference = abs(transactionAmount - paymentAmount)
        if difference == 0 { score += 4 }
        else if difference <= max(100, paymentAmount / 20) { score += 2 }

        let transactionWords = words(in: transaction.title)
        let paymentWords = words(in: payment.name)
        if !transactionWords.isDisjoint(with: paymentWords) { score += 4 }
        if let category = transaction.category,
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
