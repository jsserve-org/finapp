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
        let settings = try context.fetch(FetchDescriptor<SyncSetting>())
        let cursor = settings.first(where: { $0.key == "cursor" })?.value

        // 1. Drain the outbox alongside the pull so accepted offline edits
        //    come back in the same change feed.
        let pending = try context.fetch(FetchDescriptor<PendingMutation>(sortBy: [SortDescriptor(\.createdAt)]))
        let pendingAccounts = try context.fetch(FetchDescriptor<PendingAccountMutation>(sortBy: [SortDescriptor(\.createdAt)]))
        let accountOperations: [SyncOperation] = try pendingAccounts.compactMap { mutation in
            guard let account = try fetchOne(CachedAccount.self, id: mutation.entityId, context: context) else { return nil }
            let dto = AccountDTO(id: account.id, name: account.name, institution: account.institution, kind: account.kind, balance: Money(amountMinor: account.amountMinor, currency: account.currency), updatedAt: account.updatedAt)
            return SyncOperation(mutationId: mutation.mutationId, entity: "account", action: "upsert", entityId: account.id, value: .init(account: dto), baseVersion: 0)
        }
        var accepted = 0
        if !pending.isEmpty || !pendingAccounts.isEmpty {
            let result = try await api.sync(cursor: cursor, operations: accountOperations + pending.map(\.operation))
            let acceptedIds = Set(result.acceptedMutationIds)
            for mutation in pending where acceptedIds.contains(mutation.mutationId) {
                context.delete(mutation)
                accepted += 1
            }
            for mutation in pendingAccounts where acceptedIds.contains(mutation.mutationId) {
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
            default:
                continue
            }
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
            lastError = String(describing: error)
        }
    }
}
