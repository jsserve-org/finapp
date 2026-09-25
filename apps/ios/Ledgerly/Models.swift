import Foundation
import SwiftData

enum LedgerlyISODate {
    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let standard = Date.ISO8601FormatStyle()

    static func parse(_ value: String) -> Date? {
        if let date = try? fractional.parse(value) { return date }
        return try? standard.parse(value)
    }
}

// MARK: - API DTOs (mirror the Hono contracts in apps/api/src)

struct Money: Codable, Equatable { let amountMinor: Int; let currency: String }

struct AccountDTO: Codable, Equatable, Identifiable {
    let id, name, institution, kind: String
    let balance: Money
    let updatedAt: String
}

struct TransactionDTO: Codable, Equatable, Identifiable {
    let id, accountId, description: String
    let amount: Money
    let originalAmount: Money?
    let bookedAt: String
    let pending: Bool
    let category: String?
    let recurringPaymentId: String?
    let source: String?
    let expensePurpose: String?
    let reimbursementStatus: String?
    let reimbursementTransactionId: String?
    let refundTransactionId: String?
    let refundedTransactionId: String?
    let transferId: String?
    let transferAccountId: String?
    let transferDirection: String?
    let updatedAt: String

    init(id: String, accountId: String, description: String, amount: Money, originalAmount: Money? = nil, bookedAt: String, pending: Bool, category: String?, recurringPaymentId: String? = nil, source: String? = nil, expensePurpose: String? = nil, reimbursementStatus: String? = nil, reimbursementTransactionId: String? = nil, refundTransactionId: String? = nil, refundedTransactionId: String? = nil, transferId: String? = nil, transferAccountId: String? = nil, transferDirection: String? = nil, updatedAt: String) {
        self.id = id; self.accountId = accountId; self.description = description; self.amount = amount
        self.originalAmount = originalAmount
        self.bookedAt = bookedAt; self.pending = pending; self.category = category
        self.recurringPaymentId = recurringPaymentId; self.source = source; self.expensePurpose = expensePurpose
        self.reimbursementStatus = reimbursementStatus; self.reimbursementTransactionId = reimbursementTransactionId
        self.refundTransactionId = refundTransactionId; self.refundedTransactionId = refundedTransactionId
        self.transferId = transferId; self.transferAccountId = transferAccountId; self.transferDirection = transferDirection
        self.updatedAt = updatedAt
    }
}

struct RecurringPaymentDTO: Codable, Equatable, Identifiable {
    let id, name: String
    let amountMinor: Int
    let currency, frequency: String
    let nextDate: Date
    let accountId: String?
    let category: String
    let isActive: Bool
}

struct StockHoldingDTO: Codable, Equatable, Identifiable {
    let id, symbol, name, currency: String
    let quantity: Double
    let averageCostMinor, currentPriceMinor: Int
    let linkedAccountId: String?
    let updatedAt: String
}

struct StockTradeDTO: Codable, Equatable, Identifiable {
    let id, holdingId, symbol, side, currency: String
    let quantity: Double
    let priceMinor, feesMinor: Int
    let tradedAt: String
    let linkedAccountId: String?
}

struct SyncChange: Codable {
    let sequence: Int
    let entity: String
    let entityId: String
    let action: String
    let value: JSONValue?
}

struct SyncResponse: Codable {
    let cursor: String
    let changes: [SyncChange]
    let acceptedMutationIds: [String]
}

/// Mutation payload exchanged with the sync API for accounts, transactions,
/// and recurring bills.
struct SyncOperation: Encodable {
    let mutationId: String
    let entity: String
    let action: String
    let entityId: String
    let value: OperationValue?
    let baseVersion: Int

    struct OperationValue: Encodable {
        var description: String?
        var category: String?
        var recurringPaymentId: String?
        var includesRecurringPaymentId: Bool
        var account: AccountDTO?
        var transaction: TransactionDTO?
        var recurringPayment: RecurringPaymentDTO?
        var stockHolding: StockHoldingDTO?
        var stockTrade: StockTradeDTO?

        init(description: String? = nil, category: String? = nil, recurringPaymentId: String? = nil, includesRecurringPaymentId: Bool = false, account: AccountDTO? = nil, transaction: TransactionDTO? = nil, recurringPayment: RecurringPaymentDTO? = nil, stockHolding: StockHoldingDTO? = nil, stockTrade: StockTradeDTO? = nil) {
            self.description = description; self.category = category; self.recurringPaymentId = recurringPaymentId
            self.includesRecurringPaymentId = includesRecurringPaymentId
            self.account = account; self.transaction = transaction; self.recurringPayment = recurringPayment
            self.stockHolding = stockHolding; self.stockTrade = stockTrade
        }

        enum CodingKeys: String, CodingKey { case description; case category; case recurringPaymentId }
        func encode(to encoder: Encoder) throws {
            if let account { try account.encode(to: encoder); return }
            if let transaction { try transaction.encode(to: encoder); return }
            if let recurringPayment { try recurringPayment.encode(to: encoder); return }
            if let stockHolding { try stockHolding.encode(to: encoder); return }
            if let stockTrade { try stockTrade.encode(to: encoder); return }
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let description, !description.isEmpty { try container.encode(description, forKey: .description) }
            if let category { try container.encode(category, forKey: .category) }
            if includesRecurringPaymentId {
                if let recurringPaymentId { try container.encode(recurringPaymentId, forKey: .recurringPaymentId) }
                else { try container.encodeNil(forKey: .recurringPaymentId) }
            }
        }
    }

    init(mutationId: String, entity: String = "transaction", action: String, entityId: String, value: OperationValue?, baseVersion: Int) {
        self.mutationId = mutationId; self.entity = entity; self.action = action; self.entityId = entityId; self.value = value; self.baseVersion = baseVersion
    }
}

@Model final class PendingAccountMutation {
    @Attribute(.unique) var mutationId: String
    var entityId: String
    var action: String = "upsert"
    var createdAt: Date
    init(entityId: String, action: String = "upsert") {
        mutationId = UUID().uuidString.lowercased()
        self.entityId = entityId
        self.action = action
        createdAt = Date()
    }
}

@Model final class PendingTransactionCreate {
    @Attribute(.unique) var mutationId: String
    var entityId: String
    var createdAt: Date

    init(entityId: String) {
        mutationId = UUID().uuidString.lowercased()
        self.entityId = entityId
        createdAt = Date()
    }
}

@Model final class PendingRecurringMutation {
    @Attribute(.unique) var mutationId: String
    var entityId: String
    var action: String
    var createdAt: Date

    init(entityId: String, action: String) {
        mutationId = UUID().uuidString.lowercased()
        self.entityId = entityId
        self.action = action
        createdAt = Date()
    }
}

@Model final class PendingStockMutation {
    @Attribute(.unique) var mutationId: String
    var entityId: String
    var entityKind: String = "stockHolding"
    var action: String
    var createdAt: Date

    init(entityId: String, entity: String, action: String = "upsert") {
        mutationId = UUID().uuidString.lowercased()
        self.entityId = entityId
        self.entityKind = entity
        self.action = action
        createdAt = Date()
    }
}

/// Opaque JSON payload attached to a sync change.
enum JSONValue: Codable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode(Bool.self) { self = .bool(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try box.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self {
        case .object(let value): try box.encode(value)
        case .array(let value): try box.encode(value)
        case .string(let value): try box.encode(value)
        case .number(let value): try box.encode(value)
        case .bool(let value): try box.encode(value)
        case .null: try box.encodeNil()
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

// MARK: - SwiftData cache

@Model final class CachedAccount {
    @Attribute(.unique) var id: String
    var name: String
    var institution: String
    var kind: String
    var amountMinor: Int
    var currency: String
    var version: Int
    var updatedAt: String

    init(dto: AccountDTO, initialVersion: Int = 1) {
        id = dto.id
        name = dto.name
        institution = dto.institution
        kind = dto.kind
        amountMinor = dto.balance.amountMinor
        currency = dto.balance.currency
        version = initialVersion
        updatedAt = dto.updatedAt
    }

    init(name: String, institution: String, kind: String, amountMinor: Int, currency: String) {
        id = UUID().uuidString.lowercased()
        self.name = name
        self.institution = institution
        self.kind = kind
        self.amountMinor = amountMinor
        self.currency = currency
        version = 1
        updatedAt = ISO8601DateFormatter().string(from: Date())
    }

    func apply(_ dto: AccountDTO, version: Int) {
        name = dto.name
        institution = dto.institution
        kind = dto.kind
        amountMinor = dto.balance.amountMinor
        currency = dto.balance.currency
        self.version = version
        updatedAt = dto.updatedAt
    }

    var displayKind: String {
        switch kind {
        case "sharedCredit": "Someone else's card"
        case "credit": "Credit card"
        default: kind.capitalized
        }
    }

    var isIncludedInNetWorth: Bool { kind != "sharedCredit" }
}

@Model final class CachedTransaction {
    @Attribute(.unique) var id: String
    var accountId: String
    var title: String
    var amountMinor: Int
    var currency: String
    var originalAmountMinor: Int?
    var originalCurrency: String?
    var bookedAt: String
    var pending: Bool
    var category: String?
    var recurringPaymentId: String?
    var source: String?
    var expensePurpose: String?
    var reimbursementStatus: String?
    var reimbursementTransactionId: String?
    var refundTransactionId: String?
    var refundedTransactionId: String?
    var transferId: String?
    var transferAccountId: String?
    var transferDirection: String?
    var version: Int
    var updatedAt: String

    init(dto: TransactionDTO, initialVersion: Int = 1) {
        id = dto.id
        accountId = dto.accountId
        title = dto.description
        amountMinor = dto.amount.amountMinor
        currency = dto.amount.currency
        originalAmountMinor = dto.originalAmount?.amountMinor
        originalCurrency = dto.originalAmount?.currency
        bookedAt = dto.bookedAt
        pending = dto.pending
        category = dto.category
        recurringPaymentId = dto.recurringPaymentId
        source = dto.source
        expensePurpose = dto.expensePurpose
        reimbursementStatus = dto.reimbursementStatus
        reimbursementTransactionId = dto.reimbursementTransactionId
        refundTransactionId = dto.refundTransactionId
        refundedTransactionId = dto.refundedTransactionId
        transferId = dto.transferId
        transferAccountId = dto.transferAccountId
        transferDirection = dto.transferDirection
        version = initialVersion
        updatedAt = dto.updatedAt
    }

    func apply(_ dto: TransactionDTO, version: Int) {
        accountId = dto.accountId
        title = dto.description
        amountMinor = dto.amount.amountMinor
        currency = dto.amount.currency
        originalAmountMinor = dto.originalAmount?.amountMinor
        originalCurrency = dto.originalAmount?.currency
        bookedAt = dto.bookedAt
        pending = dto.pending
        category = dto.category
        recurringPaymentId = dto.recurringPaymentId
        source = dto.source
        expensePurpose = dto.expensePurpose
        reimbursementStatus = dto.reimbursementStatus
        reimbursementTransactionId = dto.reimbursementTransactionId
        refundTransactionId = dto.refundTransactionId
        refundedTransactionId = dto.refundedTransactionId
        transferId = dto.transferId
        transferAccountId = dto.transferAccountId
        transferDirection = dto.transferDirection
        self.version = version
        updatedAt = dto.updatedAt
    }

    var bookedDate: Date? {
        LedgerlyISODate.parse(bookedAt)
    }

    var updatedDate: Date? {
        LedgerlyISODate.parse(updatedAt)
    }

    var presentedAmountMinor: Int {
        isAwaitingSettlement ? (originalAmountMinor ?? 0) : amountMinor
    }

    var presentedCurrency: String {
        isAwaitingSettlement ? (originalCurrency ?? currency) : currency
    }

    var isAwaitingSettlement: Bool {
        pending && amountMinor == 0 && originalAmountMinor != nil && originalCurrency != nil
    }
}

@Model final class SyncSetting {
    @Attribute(.unique) var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

@Model final class RecurringPayment {
    @Attribute(.unique) var id: String
    var name: String
    var amountMinor: Int
    var currency: String
    var frequency: String
    var nextDate: Date
    var accountId: String?
    var category: String
    var isActive: Bool

    init(id: String = UUID().uuidString.lowercased(), name: String, amountMinor: Int, currency: String, frequency: String, nextDate: Date, accountId: String?, category: String, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.amountMinor = amountMinor
        self.currency = currency
        self.frequency = frequency
        self.nextDate = nextDate
        self.accountId = accountId
        self.category = category
        self.isActive = isActive
    }

    var frequencyLabel: String {
        switch frequency {
        case "weekly": "Weekly"
        case "everyTwoWeeks": "Every 2 weeks"
        case "yearly": "Yearly"
        case "everyTwoYears": "Every 2 years"
        default: "Monthly"
        }
    }
}

@Model final class StockHolding {
    @Attribute(.unique) var id: String
    var symbol: String
    var name: String
    var quantity: Double
    var averageCostMinor: Int
    var currentPriceMinor: Int
    var currency: String
    var linkedAccountId: String?
    var updatedAt: String

    init(id: String = UUID().uuidString.lowercased(), symbol: String, name: String, quantity: Double, averageCostMinor: Int, currentPriceMinor: Int, currency: String, linkedAccountId: String?, updatedAt: String = ISO8601DateFormatter().string(from: Date())) {
        self.id = id; self.symbol = symbol; self.name = name; self.quantity = quantity
        self.averageCostMinor = averageCostMinor; self.currentPriceMinor = currentPriceMinor
        self.currency = currency; self.linkedAccountId = linkedAccountId; self.updatedAt = updatedAt
    }

    var marketValueMinor: Int { Int((quantity * Double(currentPriceMinor)).rounded()) }
    var costBasisMinor: Int { Int((quantity * Double(averageCostMinor)).rounded()) }
    var gainLossMinor: Int { marketValueMinor - costBasisMinor }
}

enum NetWorthCalculator {
    static func totals(accounts: [CachedAccount], holdings: [StockHolding]) -> [String: Int] {
        var result = Dictionary(grouping: accounts.filter(\.isIncludedInNetWorth), by: \.currency)
            .mapValues { $0.reduce(0) { $0 + $1.amountMinor } }
        for holding in holdings {
            result[holding.currency, default: 0] += holding.marketValueMinor
        }
        return result
    }
}

@Model final class StockTrade {
    @Attribute(.unique) var id: String
    var holdingId: String
    var symbol: String
    var side: String
    var quantity: Double
    var priceMinor: Int
    var feesMinor: Int
    var currency: String
    var tradedAt: String
    var linkedAccountId: String?

    init(id: String = UUID().uuidString.lowercased(), holdingId: String, symbol: String, side: String, quantity: Double, priceMinor: Int, feesMinor: Int, currency: String, tradedAt: String, linkedAccountId: String?) {
        self.id = id; self.holdingId = holdingId; self.symbol = symbol; self.side = side
        self.quantity = quantity; self.priceMinor = priceMinor; self.feesMinor = feesMinor
        self.currency = currency; self.tradedAt = tradedAt; self.linkedAccountId = linkedAccountId
    }
}

/// Local mutation queue for edits made while offline. Entries are flushed
/// through `POST /v1/sync` operations and dropped once accepted.
@Model final class PendingMutation {
    @Attribute(.unique) var mutationId: String
    var entityId: String
    var action: String
    var newDescription: String?
    var newCategory: String?
    var newRecurringPaymentId: String?
    var updatesRecurringPayment: Bool = false
    var baseVersion: Int
    var createdAt: Date

    init(entityId: String, action: String, newDescription: String?, newCategory: String?, newRecurringPaymentId: String? = nil, updatesRecurringPayment: Bool = false, baseVersion: Int, createdAt: Date = Date()) {
        mutationId = UUID().uuidString.lowercased()
        self.entityId = entityId
        self.action = action
        self.newDescription = newDescription
        self.newCategory = newCategory
        self.newRecurringPaymentId = newRecurringPaymentId
        self.updatesRecurringPayment = updatesRecurringPayment
        self.baseVersion = baseVersion
        self.createdAt = createdAt
    }

    var operation: SyncOperation {
        SyncOperation(
            mutationId: mutationId,
            action: action,
            entityId: entityId,
            value: action == "delete" ? nil : SyncOperation.OperationValue(description: newDescription, category: newCategory, recurringPaymentId: newRecurringPaymentId, includesRecurringPaymentId: updatesRecurringPayment),
            baseVersion: baseVersion
        )
    }
}
