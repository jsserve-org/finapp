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
        if imported.recurringPaymentId == nil { imported.recurringPaymentId = manual.recurringPaymentId }
        if imported.reimbursementStatus == nil { imported.reimbursementStatus = manual.reimbursementStatus }
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
