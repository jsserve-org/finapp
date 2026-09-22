import Foundation
import SwiftData

struct Money: Codable { let amountMinor: Int; let currency: String }
struct AccountDTO: Codable, Identifiable { let id, name, institution, kind: String; let balance: Money; let updatedAt: String }
struct TransactionDTO: Codable, Identifiable { let id, accountId, description: String; let amount: Money; let bookedAt: String; let pending: Bool; let category: String?; let updatedAt: String }
struct SyncChange: Codable { let sequence: Int; let entity, entityId, action: String; let value: JSONValue? }
struct SyncResponse: Codable { let cursor: String; let changes: [SyncChange]; let acceptedMutationIds: [String] }

enum JSONValue: Codable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let value = try? box.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? box.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? box.decode(String.self) { self = .string(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else { self = .bool(try box.decode(Bool.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self { case .object(let v): try box.encode(v); case .array(let v): try box.encode(v); case .string(let v): try box.encode(v); case .number(let v): try box.encode(v); case .bool(let v): try box.encode(v); case .null: try box.encodeNil() }
    }
}

@Model final class CachedAccount {
    @Attribute(.unique) var id: String
    var name: String; var institution: String; var kind: String; var amountMinor: Int; var currency: String; var updatedAt: String
    init(dto: AccountDTO) { id = dto.id; name = dto.name; institution = dto.institution; kind = dto.kind; amountMinor = dto.balance.amountMinor; currency = dto.balance.currency; updatedAt = dto.updatedAt }
}

@Model final class CachedTransaction {
    @Attribute(.unique) var id: String
    var accountId: String; var title: String; var amountMinor: Int; var currency: String; var bookedAt: String; var pending: Bool; var category: String?; var updatedAt: String
    init(dto: TransactionDTO) { id = dto.id; accountId = dto.accountId; title = dto.description; amountMinor = dto.amount.amountMinor; currency = dto.amount.currency; bookedAt = dto.bookedAt; pending = dto.pending; category = dto.category; updatedAt = dto.updatedAt }
}

@Model final class SyncSetting {
    @Attribute(.unique) var key: String
    var value: String
    init(key: String, value: String) { self.key = key; self.value = value }
}
