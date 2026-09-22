import Foundation
import SwiftData

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
    let bookedAt: String
    let pending: Bool
    let category: String?
    let updatedAt: String
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
        var account: AccountDTO?
        var transaction: TransactionDTO?
        var recurringPayment: RecurringPaymentDTO?

        init(description: String? = nil, category: String? = nil, account: AccountDTO? = nil, transaction: TransactionDTO? = nil, recurringPayment: RecurringPaymentDTO? = nil) {
            self.description = description; self.category = category; self.account = account; self.transaction = transaction; self.recurringPayment = recurringPayment
        }

        enum CodingKeys: String, CodingKey { case description; case category }
        func encode(to encoder: Encoder) throws {
            if let account { try account.encode(to: encoder); return }
            if let transaction { try transaction.encode(to: encoder); return }
            if let recurringPayment { try recurringPayment.encode(to: encoder); return }
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let description, !description.isEmpty { try container.encode(description, forKey: .description) }
            if let category { try container.encode(category, forKey: .category) }
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

    var displayKind: String { kind.capitalized }
}

@Model final class CachedTransaction {
    @Attribute(.unique) var id: String
    var accountId: String
    var title: String
    var amountMinor: Int
    var currency: String
    var bookedAt: String
    var pending: Bool
    var category: String?
    var version: Int
    var updatedAt: String

    init(dto: TransactionDTO, initialVersion: Int = 1) {
        id = dto.id
        accountId = dto.accountId
        title = dto.description
        amountMinor = dto.amount.amountMinor
        currency = dto.amount.currency
        bookedAt = dto.bookedAt
        pending = dto.pending
        category = dto.category
        version = initialVersion
        updatedAt = dto.updatedAt
    }

    func apply(_ dto: TransactionDTO, version: Int) {
        accountId = dto.accountId
        title = dto.description
        amountMinor = dto.amount.amountMinor
        currency = dto.amount.currency
        bookedAt = dto.bookedAt
        pending = dto.pending
        category = dto.category
        self.version = version
        updatedAt = dto.updatedAt
    }

    var bookedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: bookedAt) ?? ISO8601DateFormatter().date(from: bookedAt)
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
        default: "Monthly"
        }
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
    var baseVersion: Int
    var createdAt: Date

    init(entityId: String, action: String, newDescription: String?, newCategory: String?, baseVersion: Int, createdAt: Date = Date()) {
        mutationId = UUID().uuidString.lowercased()
        self.entityId = entityId
        self.action = action
        self.newDescription = newDescription
        self.newCategory = newCategory
        self.baseVersion = baseVersion
        self.createdAt = createdAt
    }

    var operation: SyncOperation {
        SyncOperation(
            mutationId: mutationId,
            action: action,
            entityId: entityId,
            value: action == "delete" ? nil : SyncOperation.OperationValue(description: newDescription, category: newCategory),
            baseVersion: baseVersion
        )
    }
}
