import Foundation
import SwiftData

/// Applies `POST /v1/sync` responses to the SwiftData cache and drains the
/// local mutation outbox. Confined to the main actor because the UI's
/// `ModelContext` must only be touched from one executor.
@MainActor
struct SyncEngine {
    let api: APIClient

    /// Applies changes, persists the cursor, and flushes pending mutations.
    /// Returns the number of pending mutations that were accepted.
    @discardableResult
    func runSync(context: ModelContext) async throws -> Int {
        let serverConfig = try await api.serverConfig()
        let compatibility = LedgerlyCompatibility.evaluate(serverConfig)
        guard compatibility.canSync else { throw APIError.incompatible(compatibility.message) }
        let settings = try context.fetch(FetchDescriptor<SyncSetting>())
        let cursor = settings.first(where: { $0.key == "cursor" })?.value

        // 1. Drain the outbox alongside the pull so accepted offline edits
        //    come back in the same change feed.
        let pending = try context.fetch(FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)]))
        let pendingAccounts = try context.fetch(FetchDescriptor<PendingAccountMutation>(sortBy: [SortDescriptor(\.createdAt)]))
        let pendingTransactions = try context.fetch(FetchDescriptor<PendingTransactionCreate>(sortBy: [SortDescriptor(\.createdAt)]))
        let pendingRecurring = try context.fetch(FetchDescriptor<PendingRecurringMutation>(sortBy: [SortDescriptor(\.createdAt)]))
        let pendingStocks = try context.fetch(FetchDescriptor<PendingStockMutation>(sortBy: [SortDescriptor(\.createdAt)]))
        let accountOperations: [SyncOperation] = try pendingAccounts.compactMap { mutation in
            if mutation.action == "delete" {
                return SyncOperation(mutationId: mutation.mutationId, entity: "account", action: "delete", entityId: mutation.entityId, value: nil, baseVersion: 0)
            }
            guard let account = try fetchOne(CachedAccount.self, id: mutation.entityId, context: context) else { return nil }
            let dto = AccountDTO(id: account.id, name: account.name, institution: account.institution, kind: account.kind, balance: Money(amountMinor: account.amountMinor, currency: account.currency), updatedAt: account.updatedAt)
            return SyncOperation(mutationId: mutation.mutationId, entity: "account", action: "upsert", entityId: account.id, value: .init(account: dto), baseVersion: 0)
        }
        let transactionOperations: [SyncOperation] = try pendingTransactions.compactMap { mutation in
            guard let transaction = try fetchOne(CachedTransaction.self, id: mutation.entityId, context: context) else { return nil }
            let dto = TransactionDTO(id: transaction.id, accountId: transaction.accountId, description: transaction.title, amount: Money(amountMinor: transaction.amountMinor, currency: transaction.currency), bookedAt: transaction.bookedAt, pending: transaction.pending, category: transaction.category, recurringPaymentId: transaction.recurringPaymentId, source: transaction.source, expensePurpose: transaction.expensePurpose, reimbursementStatus: transaction.reimbursementStatus, reimbursementTransactionId: transaction.reimbursementTransactionId, transferId: transaction.transferId, transferAccountId: transaction.transferAccountId, transferDirection: transaction.transferDirection, updatedAt: transaction.updatedAt)
            return SyncOperation(mutationId: mutation.mutationId, action: "upsert", entityId: transaction.id, value: .init(transaction: dto), baseVersion: 0)
        }
        let recurringOperations: [SyncOperation] = try pendingRecurring.compactMap { mutation in
            if mutation.action == "delete" {
                return SyncOperation(mutationId: mutation.mutationId, entity: "recurringPayment", action: "delete", entityId: mutation.entityId, value: nil, baseVersion: 0)
            }
            guard let payment = try fetchOne(RecurringPayment.self, id: mutation.entityId, context: context) else { return nil }
            let dto = RecurringPaymentDTO(id: payment.id, name: payment.name, amountMinor: payment.amountMinor, currency: payment.currency, frequency: payment.frequency, nextDate: payment.nextDate, accountId: payment.accountId, category: payment.category, isActive: payment.isActive)
            return SyncOperation(mutationId: mutation.mutationId, entity: "recurringPayment", action: "upsert", entityId: payment.id, value: .init(recurringPayment: dto), baseVersion: 0)
        }
        let stockOperations: [SyncOperation] = try pendingStocks.compactMap { mutation in
            if mutation.action == "delete" {
                return SyncOperation(mutationId: mutation.mutationId, entity: mutation.entityKind, action: "delete", entityId: mutation.entityId, value: nil, baseVersion: 0)
            }
            if mutation.entityKind == "stockHolding", let holding = try fetchOne(StockHolding.self, id: mutation.entityId, context: context) {
                let dto = StockHoldingDTO(id: holding.id, symbol: holding.symbol, name: holding.name, currency: holding.currency, quantity: holding.quantity, averageCostMinor: holding.averageCostMinor, currentPriceMinor: holding.currentPriceMinor, linkedAccountId: holding.linkedAccountId, updatedAt: holding.updatedAt)
                return SyncOperation(mutationId: mutation.mutationId, entity: mutation.entityKind, action: "upsert", entityId: holding.id, value: .init(stockHolding: dto), baseVersion: 0)
            }
            if mutation.entityKind == "stockTrade", let trade = try fetchOne(StockTrade.self, id: mutation.entityId, context: context) {
                let dto = StockTradeDTO(id: trade.id, holdingId: trade.holdingId, symbol: trade.symbol, side: trade.side, currency: trade.currency, quantity: trade.quantity, priceMinor: trade.priceMinor, feesMinor: trade.feesMinor, tradedAt: trade.tradedAt, linkedAccountId: trade.linkedAccountId)
                return SyncOperation(mutationId: mutation.mutationId, entity: mutation.entityKind, action: "upsert", entityId: trade.id, value: .init(stockTrade: dto), baseVersion: 0)
            }
            return nil
        }
        var accepted = 0
        if !pending.isEmpty || !pendingAccounts.isEmpty || !pendingTransactions.isEmpty || !pendingRecurring.isEmpty || !pendingStocks.isEmpty {
            let result = try await api.sync(cursor: cursor, operations: accountOperations + transactionOperations + recurringOperations + stockOperations + pending.map(\.operation))
            let acceptedIds = Set(result.acceptedMutationIds)
            for mutation in pending where acceptedIds.contains(mutation.mutationId) {
                context.delete(mutation)
                accepted += 1
            }
            for mutation in pendingAccounts where acceptedIds.contains(mutation.mutationId) {
                context.delete(mutation)
                accepted += 1
            }
            for mutation in pendingTransactions where acceptedIds.contains(mutation.mutationId) {
                context.delete(mutation)
                accepted += 1
            }
            for mutation in pendingRecurring where acceptedIds.contains(mutation.mutationId) {
                context.delete(mutation)
                accepted += 1
            }
            for mutation in pendingStocks where acceptedIds.contains(mutation.mutationId) {
                context.delete(mutation)
                accepted += 1
            }
            try apply(result.changes, context: context)
            saveCursor(result.cursor, settings: settings, context: context)
            try context.save()
            return accepted
        }

        let result = try await api.sync(cursor: cursor)
        try apply(result.changes, context: context)
        saveCursor(result.cursor, settings: settings, context: context)
        try context.save()
        return 0
    }

    /// Pure cache-application step, shared by both sync paths.
    func apply(_ changes: [SyncChange], context: ModelContext) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for change in changes {
            let entityID = change.entityId
            if change.action == "delete" {
                if change.entity == "account" {
                    try fetchOne(CachedAccount.self, id: entityID, context: context).map(context.delete)
                }
                if change.entity == "transaction" {
                    try fetchOne(CachedTransaction.self, id: entityID, context: context).map(context.delete)
                }
                if change.entity == "recurringPayment" {
                    try fetchOne(RecurringPayment.self, id: entityID, context: context).map(context.delete)
                }
                if change.entity == "stockHolding" { try fetchOne(StockHolding.self, id: entityID, context: context).map(context.delete) }
                if change.entity == "stockTrade" { try fetchOne(StockTrade.self, id: entityID, context: context).map(context.delete) }
                continue
            }
            guard let value = change.value else { continue }
            let data = try encoder.encode(value)

            switch change.entity {
            case "account":
                let dto = try decoder.decode(AccountDTO.self, from: data)
                if let item = try fetchOne(CachedAccount.self, id: entityID, context: context) {
                    item.apply(dto, version: change.sequence)
                } else {
                    context.insert(CachedAccount(dto: dto, initialVersion: change.sequence))
                }
            case "transaction":
                let dto = try decoder.decode(TransactionDTO.self, from: data)
                if let item = try fetchOne(CachedTransaction.self, id: entityID, context: context) {
                    item.apply(dto, version: change.sequence)
                } else {
                    context.insert(CachedTransaction(dto: dto, initialVersion: change.sequence))
                }
            case "recurringPayment":
                let dto = try decoder.decode(RecurringPaymentDTO.self, from: data)
                if let item = try fetchOne(RecurringPayment.self, id: entityID, context: context) {
                    item.name = dto.name
                    item.amountMinor = dto.amountMinor
                    item.currency = dto.currency
                    item.frequency = dto.frequency
                    item.nextDate = dto.nextDate
                    item.accountId = dto.accountId
                    item.category = dto.category
                    item.isActive = dto.isActive
                } else {
                    context.insert(RecurringPayment(id: dto.id, name: dto.name, amountMinor: dto.amountMinor, currency: dto.currency, frequency: dto.frequency, nextDate: dto.nextDate, accountId: dto.accountId, category: dto.category, isActive: dto.isActive))
                }
            case "stockHolding":
                let dto = try decoder.decode(StockHoldingDTO.self, from: data)
                if let item = try fetchOne(StockHolding.self, id: entityID, context: context) {
                    item.symbol = dto.symbol; item.name = dto.name; item.quantity = dto.quantity
                    item.averageCostMinor = dto.averageCostMinor; item.currentPriceMinor = dto.currentPriceMinor
                    item.currency = dto.currency; item.linkedAccountId = dto.linkedAccountId; item.updatedAt = dto.updatedAt
                } else {
                    context.insert(StockHolding(id: dto.id, symbol: dto.symbol, name: dto.name, quantity: dto.quantity, averageCostMinor: dto.averageCostMinor, currentPriceMinor: dto.currentPriceMinor, currency: dto.currency, linkedAccountId: dto.linkedAccountId, updatedAt: dto.updatedAt))
                }
            case "stockTrade":
                let dto = try decoder.decode(StockTradeDTO.self, from: data)
                if let item = try fetchOne(StockTrade.self, id: entityID, context: context) {
                    item.holdingId = dto.holdingId; item.symbol = dto.symbol; item.side = dto.side
                    item.quantity = dto.quantity; item.priceMinor = dto.priceMinor; item.feesMinor = dto.feesMinor
                    item.currency = dto.currency; item.tradedAt = dto.tradedAt; item.linkedAccountId = dto.linkedAccountId
                } else {
                    context.insert(StockTrade(id: dto.id, holdingId: dto.holdingId, symbol: dto.symbol, side: dto.side, quantity: dto.quantity, priceMinor: dto.priceMinor, feesMinor: dto.feesMinor, currency: dto.currency, tradedAt: dto.tradedAt, linkedAccountId: dto.linkedAccountId))
                }
            default:
                continue
            }
        }
        let transactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        let recurringPayments = try context.fetch(FetchDescriptor<RecurringPayment>())
        for transaction in transactions where transaction.recurringPaymentId == nil {
            autoLinkRecurringPayment(transaction, payments: recurringPayments, context: context)
        }
    }

    func saveCursor(_ cursor: String, settings: [SyncSetting], context: ModelContext) {
        if let setting = settings.first(where: { $0.key == "cursor" }) {
            setting.value = cursor
        } else {
            context.insert(SyncSetting(key: "cursor", value: cursor))
        }
    }

    private func fetchOne<T: PersistentModel>(_ type: T.Type, id: String, context: ModelContext) throws -> T? {
        let modelID = id
        let descriptor = FetchDescriptor<T>()
        return try context.fetch(descriptor).first(where: { $0.id as? String == modelID })
    }
}

/// UI-facing observable wrapper around `SyncEngine`.
@MainActor
@Observable final class SyncController {
    var isSyncing = false
    var isOffline = false
    var lastError: String?
    var lastSyncedAt: Date?

    private let engine: SyncEngine

    init(api: APIClient = .shared) {
        engine = SyncEngine(api: api)
    }

    func refresh(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await engine.runSync(context: context)
            isOffline = false
            lastError = nil
            lastSyncedAt = Date()
        } catch {
            isOffline = true
            lastError = error.localizedDescription
        }
    }
}
