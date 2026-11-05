import Foundation
import SwiftData

struct RecurringPaymentMatch {
    let payment: RecurringPayment
    let score: Int
    let shouldAutoLink: Bool
}

enum RecurringPaymentMatcher {
    static func linkablePayments(accountID: String, payments: [RecurringPayment]) -> [RecurringPayment] {
        payments.filter { $0.isActive && ($0.accountId == nil || $0.accountId == accountID) }
    }

    static func compatiblePayments(for transaction: CachedTransaction, payments: [RecurringPayment]) -> [RecurringPayment] {
        compatiblePayments(currency: transaction.originalCurrency ?? transaction.currency, accountID: transaction.accountId, payments: payments)
    }

    static func compatiblePayments(currency: String, accountID: String, payments: [RecurringPayment]) -> [RecurringPayment] {
        linkablePayments(accountID: accountID, payments: payments).filter { $0.currency == currency }
    }

    static func bestMatch(for transaction: CachedTransaction, payments: [RecurringPayment]) -> RecurringPaymentMatch? {
        bestMatch(
            title: transaction.title,
            amountMinor: transaction.originalAmountMinor ?? transaction.amountMinor,
            currency: transaction.originalCurrency ?? transaction.currency,
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
        let automatic = compatiblePayments(currency: currency, accountID: accountID, payments: payments).filter {
            $0.accountId == accountID && amountMinor < 0 && Double(amountMinor).magnitude == Double($0.amountMinor) && !words(in: title).isDisjoint(with: words(in: $0.name))
        }
        return RecurringPaymentMatch(payment: best.0, score: best.1, shouldAutoLink: automatic.count == 1 && automatic.first?.id == best.0.id)
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
    guard transaction.presentedAmountMinor < 0,
          !transaction.recurringPaymentUnlinked,
          transaction.recurringPaymentId == nil,
          let match = RecurringPaymentMatcher.bestMatch(for: transaction, payments: payments),
          match.shouldAutoLink else { return false }
    transaction.recurringPaymentId = match.payment.id
    let placeholders = (try? context.fetch(FetchDescriptor<CachedTransaction>())) ?? []
    for placeholder in placeholders where placeholder.id != transaction.id && placeholder.source == "subscription" && placeholder.pending && placeholder.recurringPaymentId == match.payment.id {
        guard let due = placeholder.bookedDate, let booked = transaction.bookedDate, SubscriptionScheduler.includesPayment(booked, due: due, frequency: match.payment.frequency, anchorDay: match.payment.scheduleAnchorDay) else { continue }
        try? AccountActionService.removePendingTransactionWrites(ids: [placeholder.id], context: context)
        context.insert(PendingMutation(entityId: placeholder.id, action: "delete", newDescription: nil, newCategory: nil, baseVersion: placeholder.version))
        context.delete(placeholder)
    }
    transaction.updatedAt = ISO8601DateFormatter().string(from: Date())
    enqueueFullTransaction(context: context, transactionID: transaction.id)
    return true
}

@MainActor
func removePendingRecurringUpserts(paymentID: String, context: ModelContext) throws {
    let pending = try context.fetch(FetchDescriptor<PendingRecurringMutation>())
    for mutation in pending where mutation.entityId == paymentID && mutation.action == "upsert" {
        context.delete(mutation)
    }
}

enum SubscriptionScheduler {
    @MainActor
    static func removeEstimates(paymentID: String, context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<CachedTransaction>(predicate: #Predicate { $0.recurringPaymentId == paymentID }))
        for entry in entries where entry.source == "subscription" && entry.pending {
            try AccountActionService.removePendingTransactionWrites(ids: [entry.id], context: context)
            context.insert(PendingMutation(entityId: entry.id, action: "delete", newDescription: nil, newCategory: nil, baseVersion: entry.version))
            context.delete(entry)
        }
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    static func nextDate(after date: Date, frequency: String, anchorDay: Int, direction: Int = 1) -> Date? {
        if frequency == "weekly" || frequency == "everyTwoWeeks" {
            return calendar.date(byAdding: .day, value: direction * (frequency == "weekly" ? 7 : 14), to: date)
        }
        let months = frequency == "monthly" ? 1 : frequency == "yearly" ? 12 : frequency == "everyTwoYears" ? 24 : 0
        guard months > 0 else { return nil }
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        parts.day = 1
        guard let first = calendar.date(from: parts), let next = calendar.date(byAdding: .month, value: direction * months, to: first), let days = calendar.range(of: .day, in: .month, for: next) else { return nil }
        let anchor = (1...31).contains(anchorDay) ? anchorDay : calendar.component(.day, from: date)
        var nextParts = calendar.dateComponents([.year, .month], from: next)
        nextParts.day = min(anchor, days.count)
        nextParts.hour = parts.hour; nextParts.minute = parts.minute; nextParts.second = parts.second
        nextParts.nanosecond = parts.nanosecond
        return calendar.date(from: nextParts)
    }

    static func includesPayment(_ booked: Date, due: Date, frequency: String, anchorDay: Int) -> Bool {
        guard let previous = nextDate(after: due, frequency: frequency, anchorDay: anchorDay, direction: -1), let next = nextDate(after: due, frequency: frequency, anchorDay: anchorDay) else { return false }
        let start = previous.addingTimeInterval(due.timeIntervalSince(previous) / 2)
        let end = due.addingTimeInterval(next.timeIntervalSince(due) / 2)
        return booked >= start && booked < end
    }

    @MainActor
    static func generateDue(context: ModelContext, now: Date = Date()) throws {
        let payments = try context.fetch(FetchDescriptor<RecurringPayment>())
        let accounts = try context.fetch(FetchDescriptor<CachedAccount>())
        var transactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        let manuallyUnlinked = Set(try context.fetch(FetchDescriptor<PendingMutation>()).filter { $0.updatesRecurringPayment && $0.newRecurringPaymentId == nil }.map(\.entityId))
        for transaction in transactions where transaction.source != "subscription" && transaction.recurringPaymentId == nil && !manuallyUnlinked.contains(transaction.id) {
            autoLinkRecurringPayment(transaction, payments: payments, context: context)
        }
        for payment in payments where payment.isActive && payment.amountMinor > 0 && payment.nextDate <= now {
            guard let account = accounts.first(where: { $0.id == payment.accountId }) else { continue }
            if !(1...31).contains(payment.scheduleAnchorDay) { payment.scheduleAnchorDay = calendar.component(.day, from: payment.nextDate) }
            var count = 0
            let previousDate = payment.nextDate
            while payment.nextDate <= now && count < 36 {
                let due = payment.nextDate
                guard let next = nextDate(after: due, frequency: payment.frequency, anchorDay: payment.scheduleAnchorDay), next > due else { break }
                let id = "subscription-\(payment.id)-\(Int64((due.timeIntervalSince1970 * 1000).rounded()))"
                let recorded = transactions.contains { transaction in
                    transaction.id == id || (transaction.source != "subscription" && transaction.recurringPaymentId == payment.id && transaction.bookedDate.map { includesPayment($0, due: due, frequency: payment.frequency, anchorDay: payment.scheduleAnchorDay) } == true)
                }
                if !recorded {
                    let timestamp = ISO8601DateFormatter().string(from: now)
                    let entry = CachedTransaction(dto: TransactionDTO(id: id, accountId: account.id, description: payment.name, amount: Money(amountMinor: 0, currency: account.currency), originalAmount: Money(amountMinor: -payment.amountMinor, currency: payment.currency), bookedAt: ISO8601DateFormatter().string(from: due), pending: true, category: payment.category, recurringPaymentId: payment.id, source: "subscription", updatedAt: timestamp), initialVersion: 0)
                    context.insert(entry)
                    context.insert(PendingTransactionCreate(entityId: id))
                    transactions.append(entry)
                }
                payment.nextDate = next
                count += 1
            }
            if payment.nextDate > previousDate {
                context.insert(PendingRecurringMutation(entityId: payment.id, action: "upsert"))
            }
        }
        try context.save()
    }
}
