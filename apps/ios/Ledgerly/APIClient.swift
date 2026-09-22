import Foundation
import Observation
import SwiftData

actor APIClient {
    static let shared = APIClient()
    private let baseURL = URL(string: "http://localhost:3000")!
    private let decoder = JSONDecoder()

    func sync(cursor: String?) async throws -> SyncResponse {
        var request = URLRequest(url: baseURL.appending(path: "/v1/sync"))
        request.httpMethod = "POST"
        request.setValue("Bearer local-development-token", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["operations": []]
        if let cursor { body["cursor"] = cursor }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try decoder.decode(SyncResponse.self, from: data)
    }
}

@MainActor
@Observable final class SyncController {
    var isSyncing = false
    var isOffline = false

    func refresh(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let settings = try context.fetch(FetchDescriptor<SyncSetting>())
            let result = try await APIClient.shared.sync(cursor: settings.first(where: { $0.key == "cursor" })?.value)
            let encoder = JSONEncoder(), decoder = JSONDecoder()
            for change in result.changes {
                let entityID = change.entityId
                if change.action == "delete" {
                    if change.entity == "account", let item = try context.fetch(FetchDescriptor<CachedAccount>(predicate: #Predicate { $0.id == entityID })).first { context.delete(item) }
                    if change.entity == "transaction", let item = try context.fetch(FetchDescriptor<CachedTransaction>(predicate: #Predicate { $0.id == entityID })).first { context.delete(item) }
                } else if let value = change.value {
                    let data = try encoder.encode(value)
                    if change.entity == "account" {
                        let dto = try decoder.decode(AccountDTO.self, from: data)
                        if let item = try context.fetch(FetchDescriptor<CachedAccount>(predicate: #Predicate { $0.id == entityID })).first {
                            item.name = dto.name; item.institution = dto.institution; item.kind = dto.kind; item.amountMinor = dto.balance.amountMinor; item.currency = dto.balance.currency; item.updatedAt = dto.updatedAt
                        } else { context.insert(CachedAccount(dto: dto)) }
                    }
                    if change.entity == "transaction" {
                        let dto = try decoder.decode(TransactionDTO.self, from: data)
                        if let item = try context.fetch(FetchDescriptor<CachedTransaction>(predicate: #Predicate { $0.id == entityID })).first {
                            item.accountId = dto.accountId; item.title = dto.description; item.amountMinor = dto.amount.amountMinor; item.currency = dto.amount.currency; item.bookedAt = dto.bookedAt; item.pending = dto.pending; item.category = dto.category; item.updatedAt = dto.updatedAt
                        } else { context.insert(CachedTransaction(dto: dto)) }
                    }
                }
            }
            if let setting = settings.first(where: { $0.key == "cursor" }) { setting.value = result.cursor } else { context.insert(SyncSetting(key: "cursor", value: result.cursor)) }
            try context.save(); isOffline = false
        } catch { isOffline = true }
    }
}
