import Foundation
import SwiftData

struct TransactionMergeCandidate: Identifiable {
    let manual: CachedTransaction
    let imported: CachedTransaction

    var id: String { "\(manual.id):\(imported.id)" }
}

enum TransactionMerger {
    static func candidate(for transaction: CachedTransaction, among transactions: [CachedTransaction]) -> TransactionMergeCandidate? {
        transactions.lazy
            .filter { $0.id != transaction.id }
            .compactMap { pair(transaction, $0) }
            .first
    }

    static func pair(_ lhs: CachedTransaction, _ rhs: CachedTransaction) -> TransactionMergeCandidate? {
        guard lhs.accountId == rhs.accountId,
              lhs.currency == rhs.currency,
              lhs.amountMinor == rhs.amountMinor,
              let lhsDate = lhs.bookedDate,
              let rhsDate = rhs.bookedDate,
              abs(lhsDate.timeIntervalSince(rhsDate)) <= 3 * 24 * 60 * 60 else { return nil }

        let manual: CachedTransaction
        let imported: CachedTransaction
        if lhs.source == "manual", isImported(rhs.source) {
            manual = lhs; imported = rhs
        } else if rhs.source == "manual", isImported(lhs.source) {
            manual = rhs; imported = lhs
        } else {
            return nil
        }
        return TransactionMergeCandidate(manual: manual, imported: imported)
    }

    @MainActor
    static func merge(_ candidate: TransactionMergeCandidate, context: ModelContext) {
        let manual = candidate.manual
        let imported = candidate.imported
        if imported.category == nil || imported.category?.isEmpty == true { imported.category = manual.category }
        if imported.expensePurpose == nil { imported.expensePurpose = manual.expensePurpose }
        if imported.originalAmountMinor == nil {
            imported.originalAmountMinor = manual.originalAmountMinor
            imported.originalCurrency = manual.originalCurrency
        }
        if imported.recurringPaymentId == nil { imported.recurringPaymentId = manual.recurringPaymentId }
        if imported.reimbursementStatus == nil { imported.reimbursementStatus = manual.reimbursementStatus }
        if imported.refundTransactionId == nil { imported.refundTransactionId = manual.refundTransactionId }
        if imported.refundedTransactionId == nil { imported.refundedTransactionId = manual.refundedTransactionId }
        imported.updatedAt = ISO8601DateFormatter().string(from: Date())
        enqueueFullTransaction(context: context, transactionID: imported.id)
        context.insert(PendingMutation(entityId: manual.id, action: "delete", newDescription: nil, newCategory: nil, baseVersion: manual.version))
        context.delete(manual)
        try? context.save()
    }

    private static func isImported(_ source: String?) -> Bool {
        guard let source else { return false }
        return source == "automation" || source == "screenshot" || source == "imported" || source == "sync"
    }
}

enum ReimbursementService {
    @MainActor
    static func link(_ original: CachedTransaction, to reimbursement: CachedTransaction, context: ModelContext) {
        guard original.amountMinor < 0, reimbursement.amountMinor > 0, original.currency == reimbursement.currency else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        original.reimbursementStatus = "reimbursed"
        original.reimbursementTransactionId = reimbursement.id
        reimbursement.reimbursementTransactionId = original.id
        original.updatedAt = now
        reimbursement.updatedAt = now
        enqueueFullTransaction(context: context, transactionID: original.id)
        enqueueFullTransaction(context: context, transactionID: reimbursement.id)
        try? context.save()
    }

    @MainActor
    static func link(_ originals: [CachedTransaction], to reimbursement: CachedTransaction, context: ModelContext) {
        let eligible = originals.filter {
            $0.amountMinor < 0 &&
            $0.currency == reimbursement.currency &&
            $0.reimbursementStatus == "pending"
        }
        guard reimbursement.amountMinor > 0,
              !eligible.isEmpty,
              eligible.reduce(0, { $0 + abs($1.amountMinor) }) <= reimbursement.amountMinor else { return }

        let now = ISO8601DateFormatter().string(from: Date())
        for original in eligible {
            original.reimbursementStatus = "reimbursed"
            original.reimbursementTransactionId = reimbursement.id
            original.updatedAt = now
            enqueueFullTransaction(context: context, transactionID: original.id)
        }
        // Keep the first expense in the legacy reverse-link field. Every expense
        // stores the reimbursement ID, so one payment can cover any number of them.
        reimbursement.reimbursementTransactionId = eligible.first?.id
        reimbursement.updatedAt = now
        enqueueFullTransaction(context: context, transactionID: reimbursement.id)
        try? context.save()
    }

    @MainActor
    static func reimburse(_ original: CachedTransaction, into account: CachedAccount, context: ModelContext) -> CachedTransaction {
        let now = ISO8601DateFormatter().string(from: Date())
        let reimbursement = CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(),
            accountId: account.id,
            description: "Reimbursement · \(original.title)",
            amount: Money(amountMinor: abs(original.amountMinor), currency: original.currency),
            bookedAt: now,
            pending: false,
            category: "Reimbursement",
            source: "reimbursement",
            expensePurpose: original.expensePurpose,
            reimbursementTransactionId: original.id,
            updatedAt: now
        ), initialVersion: 0)
        context.insert(reimbursement)
        enqueueFullTransaction(context: context, transactionID: reimbursement.id)
        original.reimbursementStatus = "reimbursed"
        original.reimbursementTransactionId = reimbursement.id
        original.updatedAt = now
        enqueueFullTransaction(context: context, transactionID: original.id)
        account.amountMinor += reimbursement.amountMinor
        account.updatedAt = now
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        return reimbursement
    }
}

enum RefundService {
    @MainActor
    static func link(expense: CachedTransaction, refund: CachedTransaction, context: ModelContext) {
        guard expense.amountMinor < 0, refund.amountMinor > 0, expense.currency == refund.currency else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        expense.refundTransactionId = refund.id
        refund.refundedTransactionId = expense.id
        expense.updatedAt = now
        refund.updatedAt = now
        enqueueFullTransaction(context: context, transactionID: expense.id)
        enqueueFullTransaction(context: context, transactionID: refund.id)
        try? context.save()
    }

    @MainActor
    static func create(for expense: CachedTransaction, into account: CachedAccount, context: ModelContext) -> CachedTransaction {
        let now = ISO8601DateFormatter().string(from: Date())
        let refund = CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(), accountId: account.id,
            description: "Refund · \(expense.title)",
            amount: Money(amountMinor: abs(expense.amountMinor), currency: expense.currency),
            bookedAt: now, pending: false, category: "Refund", source: "refund",
            refundedTransactionId: expense.id, updatedAt: now
        ), initialVersion: 0)
        context.insert(refund)
        expense.refundTransactionId = refund.id
        expense.updatedAt = now
        enqueueFullTransaction(context: context, transactionID: refund.id)
        enqueueFullTransaction(context: context, transactionID: expense.id)
        account.amountMinor += refund.amountMinor
        account.updatedAt = now
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        return refund
    }
}
