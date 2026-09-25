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
            guard let account = try fetchAccount(id: mutation.entityId, context: context) else { return nil }
            let dto = AccountDTO(id: account.id, name: account.name, institution: account.institution, kind: account.kind, balance: Money(amountMinor: account.amountMinor, currency: account.currency), updatedAt: account.updatedAt)
            return SyncOperation(mutationId: mutation.mutationId, entity: "account", action: "upsert", entityId: account.id, value: .init(account: dto), baseVersion: 0)
        }
        let transactionOperations: [SyncOperation] = try pendingTransactions.compactMap { mutation in
            guard let transaction = try fetchTransaction(id: mutation.entityId, context: context) else { return nil }
            let originalAmount = transaction.originalAmountMinor.flatMap { amount in
                transaction.originalCurrency.map { Money(amountMinor: amount, currency: $0) }
            }
            let dto = TransactionDTO(id: transaction.id, accountId: transaction.accountId, description: transaction.title, amount: Money(amountMinor: transaction.amountMinor, currency: transaction.currency), originalAmount: originalAmount, bookedAt: transaction.bookedAt, pending: transaction.pending, category: transaction.category, recurringPaymentId: transaction.recurringPaymentId, source: transaction.source, expensePurpose: transaction.expensePurpose, reimbursementStatus: transaction.reimbursementStatus, reimbursementTransactionId: transaction.reimbursementTransactionId, refundTransactionId: transaction.refundTransactionId, refundedTransactionId: transaction.refundedTransactionId, transferId: transaction.transferId, transferAccountId: transaction.transferAccountId, transferDirection: transaction.transferDirection, updatedAt: transaction.updatedAt)
            return SyncOperation(mutationId: mutation.mutationId, action: "upsert", entityId: transaction.id, value: .init(transaction: dto), baseVersion: 0)
        }
        let recurringOperations: [SyncOperation] = try pendingRecurring.compactMap { mutation in
            if mutation.action == "delete" {
                return SyncOperation(mutationId: mutation.mutationId, entity: "recurringPayment", action: "delete", entityId: mutation.entityId, value: nil, baseVersion: 0)
            }
            guard let payment = try fetchRecurringPayment(id: mutation.entityId, context: context) else { return nil }
            let dto = RecurringPaymentDTO(id: payment.id, name: payment.name, amountMinor: payment.amountMinor, currency: payment.currency, frequency: payment.frequency, nextDate: payment.nextDate, accountId: payment.accountId, category: payment.category, isActive: payment.isActive)
            return SyncOperation(mutationId: mutation.mutationId, entity: "recurringPayment", action: "upsert", entityId: payment.id, value: .init(recurringPayment: dto), baseVersion: 0)
        }
        let stockOperations: [SyncOperation] = try pendingStocks.compactMap { mutation in
            if mutation.action == "delete" {
                return SyncOperation(mutationId: mutation.mutationId, entity: mutation.entityKind, action: "delete", entityId: mutation.entityId, value: nil, baseVersion: 0)
            }
            if mutation.entityKind == "stockHolding", let holding = try fetchStockHolding(id: mutation.entityId, context: context) {
                let dto = StockHoldingDTO(id: holding.id, symbol: holding.symbol, name: holding.name, currency: holding.currency, quantity: holding.quantity, averageCostMinor: holding.averageCostMinor, currentPriceMinor: holding.currentPriceMinor, linkedAccountId: holding.linkedAccountId, updatedAt: holding.updatedAt)
                return SyncOperation(mutationId: mutation.mutationId, entity: mutation.entityKind, action: "upsert", entityId: holding.id, value: .init(stockHolding: dto), baseVersion: 0)
            }
            if mutation.entityKind == "stockTrade", let trade = try fetchStockTrade(id: mutation.entityId, context: context) {
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
        var transactionsToMatch: [CachedTransaction] = []
        var recurringPaymentsChanged = false

        let accountIDs = Array(Set(changes.lazy.filter { $0.entity == "account" }.map(\.entityId)))
        let transactionIDs = Array(Set(changes.lazy.filter { $0.entity == "transaction" }.map(\.entityId)))
        let recurringIDs = Array(Set(changes.lazy.filter { $0.entity == "recurringPayment" }.map(\.entityId)))
        let holdingIDs = Array(Set(changes.lazy.filter { $0.entity == "stockHolding" }.map(\.entityId)))
        let tradeIDs = Array(Set(changes.lazy.filter { $0.entity == "stockTrade" }.map(\.entityId)))

        var accountsByID = Dictionary(uniqueKeysWithValues: try context.fetch(
            FetchDescriptor<CachedAccount>(predicate: #Predicate { accountIDs.contains($0.id) })
        ).map { ($0.id, $0) })
        var transactionsByID = Dictionary(uniqueKeysWithValues: try context.fetch(
            FetchDescriptor<CachedTransaction>(predicate: #Predicate { transactionIDs.contains($0.id) })
        ).map { ($0.id, $0) })
        var recurringByID = Dictionary(uniqueKeysWithValues: try context.fetch(
            FetchDescriptor<RecurringPayment>(predicate: #Predicate { recurringIDs.contains($0.id) })
        ).map { ($0.id, $0) })
        var holdingsByID = Dictionary(uniqueKeysWithValues: try context.fetch(
            FetchDescriptor<StockHolding>(predicate: #Predicate { holdingIDs.contains($0.id) })
        ).map { ($0.id, $0) })
        var tradesByID = Dictionary(uniqueKeysWithValues: try context.fetch(
            FetchDescriptor<StockTrade>(predicate: #Predicate { tradeIDs.contains($0.id) })
        ).map { ($0.id, $0) })

        for change in changes {
            let entityID = change.entityId
            if change.action == "delete" {
                if change.entity == "account" {
                    accountsByID.removeValue(forKey: entityID).map(context.delete)
                }
                if change.entity == "transaction" {
                    transactionsByID.removeValue(forKey: entityID).map(context.delete)
                }
                if change.entity == "recurringPayment" {
                    recurringByID.removeValue(forKey: entityID).map(context.delete)
                    recurringPaymentsChanged = true
                }
                if change.entity == "stockHolding" { holdingsByID.removeValue(forKey: entityID).map(context.delete) }
                if change.entity == "stockTrade" { tradesByID.removeValue(forKey: entityID).map(context.delete) }
                continue
            }
            guard let value = change.value else { continue }
            let data = try encoder.encode(value)

            switch change.entity {
            case "account":
                let dto = try decoder.decode(AccountDTO.self, from: data)
                if let item = accountsByID[entityID] {
                    item.apply(dto, version: change.sequence)
                } else {
                    let item = CachedAccount(dto: dto, initialVersion: change.sequence)
                    context.insert(item)
                    accountsByID[entityID] = item
                }
            case "transaction":
                let dto = try decoder.decode(TransactionDTO.self, from: data)
                if let item = transactionsByID[entityID] {
                    item.apply(dto, version: change.sequence)
                    transactionsToMatch.append(item)
                } else {
                    let item = CachedTransaction(dto: dto, initialVersion: change.sequence)
                    context.insert(item)
                    transactionsByID[entityID] = item
                    transactionsToMatch.append(item)
                }
            case "recurringPayment":
                recurringPaymentsChanged = true
                let dto = try decoder.decode(RecurringPaymentDTO.self, from: data)
                if let item = recurringByID[entityID] {
                    item.name = dto.name
                    item.amountMinor = dto.amountMinor
                    item.currency = dto.currency
                    item.frequency = dto.frequency
                    item.nextDate = dto.nextDate
                    item.accountId = dto.accountId
                    item.category = dto.category
                    item.isActive = dto.isActive
                } else {
                    let item = RecurringPayment(id: dto.id, name: dto.name, amountMinor: dto.amountMinor, currency: dto.currency, frequency: dto.frequency, nextDate: dto.nextDate, accountId: dto.accountId, category: dto.category, isActive: dto.isActive)
                    context.insert(item)
                    recurringByID[entityID] = item
                }
            case "stockHolding":
                let dto = try decoder.decode(StockHoldingDTO.self, from: data)
                if let item = holdingsByID[entityID] {
                    item.symbol = dto.symbol; item.name = dto.name; item.quantity = dto.quantity
                    item.averageCostMinor = dto.averageCostMinor; item.currentPriceMinor = dto.currentPriceMinor
                    item.currency = dto.currency; item.linkedAccountId = dto.linkedAccountId; item.updatedAt = dto.updatedAt
                } else {
                    let item = StockHolding(id: dto.id, symbol: dto.symbol, name: dto.name, quantity: dto.quantity, averageCostMinor: dto.averageCostMinor, currentPriceMinor: dto.currentPriceMinor, currency: dto.currency, linkedAccountId: dto.linkedAccountId, updatedAt: dto.updatedAt)
                    context.insert(item)
                    holdingsByID[entityID] = item
                }
            case "stockTrade":
                let dto = try decoder.decode(StockTradeDTO.self, from: data)
                if let item = tradesByID[entityID] {
                    item.holdingId = dto.holdingId; item.symbol = dto.symbol; item.side = dto.side
                    item.quantity = dto.quantity; item.priceMinor = dto.priceMinor; item.feesMinor = dto.feesMinor
                    item.currency = dto.currency; item.tradedAt = dto.tradedAt; item.linkedAccountId = dto.linkedAccountId
                } else {
                    let item = StockTrade(id: dto.id, holdingId: dto.holdingId, symbol: dto.symbol, side: dto.side, quantity: dto.quantity, priceMinor: dto.priceMinor, feesMinor: dto.feesMinor, currency: dto.currency, tradedAt: dto.tradedAt, linkedAccountId: dto.linkedAccountId)
                    context.insert(item)
                    tradesByID[entityID] = item
                }
            default:
                continue
            }
        }
        if recurringPaymentsChanged {
            var descriptor = FetchDescriptor<CachedTransaction>(
                predicate: #Predicate { $0.recurringPaymentId == nil },
                sortBy: [SortDescriptor(\.bookedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 500
            transactionsToMatch = try context.fetch(descriptor)
        }
        guard !transactionsToMatch.isEmpty else { return }
        let recurringPayments = try context.fetch(FetchDescriptor<RecurringPayment>())
        for transaction in transactionsToMatch where transaction.recurringPaymentId == nil {
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

    private func fetchAccount(id: String, context: ModelContext) throws -> CachedAccount? {
        var descriptor = FetchDescriptor<CachedAccount>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchTransaction(id: String, context: ModelContext) throws -> CachedTransaction? {
        var descriptor = FetchDescriptor<CachedTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchRecurringPayment(id: String, context: ModelContext) throws -> RecurringPayment? {
        var descriptor = FetchDescriptor<RecurringPayment>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchStockHolding(id: String, context: ModelContext) throws -> StockHolding? {
        var descriptor = FetchDescriptor<StockHolding>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchStockTrade(id: String, context: ModelContext) throws -> StockTrade? {
        var descriptor = FetchDescriptor<StockTrade>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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
