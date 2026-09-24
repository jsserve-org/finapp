import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LedgerlyBackup: Codable {
    struct Account: Codable {
        let id: String
        let name: String
        let institution: String
        let kind: String
        let amountMinor: Int
        let currency: String
        let version: Int
        let updatedAt: String
    }

    struct Transaction: Codable {
        let id: String
        let accountId: String
        let title: String
        let amountMinor: Int
        let currency: String
        let bookedAt: String
        let pending: Bool
        let category: String?
        let recurringPaymentId: String?
        let version: Int
        let updatedAt: String
    }

    struct Recurring: Codable {
        let id: String
        let name: String
        let amountMinor: Int
        let currency: String
        let frequency: String
        let nextDate: Date
        let accountId: String?
        let category: String
        let isActive: Bool
    }

    let format: String
    let version: Int
    let exportedAt: Date
    let accounts: [Account]
    let transactions: [Transaction]
    let recurringPayments: [Recurring]
}

struct LedgerlyBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let backup: LedgerlyBackup

    init(backup: LedgerlyBackup) {
        self.backup = backup
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        backup = try LedgerlyBackupService.decoder.decode(LedgerlyBackup.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try LedgerlyBackupService.encoder.encode(backup))
    }
}

enum LedgerlyBackupService {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @MainActor
    static func create(from context: ModelContext) throws -> LedgerlyBackup {
        let accounts = try context.fetch(FetchDescriptor<CachedAccount>()).map {
            LedgerlyBackup.Account(id: $0.id, name: $0.name, institution: $0.institution, kind: $0.kind, amountMinor: $0.amountMinor, currency: $0.currency, version: $0.version, updatedAt: $0.updatedAt)
        }
        let transactions = try context.fetch(FetchDescriptor<CachedTransaction>()).map {
            LedgerlyBackup.Transaction(id: $0.id, accountId: $0.accountId, title: $0.title, amountMinor: $0.amountMinor, currency: $0.currency, bookedAt: $0.bookedAt, pending: $0.pending, category: $0.category, recurringPaymentId: $0.recurringPaymentId, version: $0.version, updatedAt: $0.updatedAt)
        }
        let recurring = try context.fetch(FetchDescriptor<RecurringPayment>()).map {
            LedgerlyBackup.Recurring(id: $0.id, name: $0.name, amountMinor: $0.amountMinor, currency: $0.currency, frequency: $0.frequency, nextDate: $0.nextDate, accountId: $0.accountId, category: $0.category, isActive: $0.isActive)
        }
        return LedgerlyBackup(format: "com.ledgerly.backup", version: 1, exportedAt: Date(), accounts: accounts, transactions: transactions, recurringPayments: recurring)
    }

    @discardableResult
    @MainActor
    static func restore(_ backup: LedgerlyBackup, into context: ModelContext) throws -> Int {
        guard backup.format == "com.ledgerly.backup", backup.version == 1 else { throw BackupError.unsupportedFormat }

        let currentAccounts = try context.fetch(FetchDescriptor<CachedAccount>())
        let currentTransactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        let currentRecurring = try context.fetch(FetchDescriptor<RecurringPayment>())
        let accountsByID = Dictionary(uniqueKeysWithValues: currentAccounts.map { ($0.id, $0) })
        let transactionsByID = Dictionary(uniqueKeysWithValues: currentTransactions.map { ($0.id, $0) })
        let recurringByID = Dictionary(uniqueKeysWithValues: currentRecurring.map { ($0.id, $0) })

        for item in backup.accounts {
            let dto = AccountDTO(id: item.id, name: item.name, institution: item.institution, kind: item.kind, balance: Money(amountMinor: item.amountMinor, currency: item.currency), updatedAt: item.updatedAt)
            if let existing = accountsByID[item.id] { existing.apply(dto, version: item.version) }
            else { context.insert(CachedAccount(dto: dto, initialVersion: item.version)) }
        }
        for item in backup.transactions {
            let dto = TransactionDTO(id: item.id, accountId: item.accountId, description: item.title, amount: Money(amountMinor: item.amountMinor, currency: item.currency), bookedAt: item.bookedAt, pending: item.pending, category: item.category, recurringPaymentId: item.recurringPaymentId, updatedAt: item.updatedAt)
            if let existing = transactionsByID[item.id] { existing.apply(dto, version: item.version) }
            else { context.insert(CachedTransaction(dto: dto, initialVersion: item.version)) }
        }
        for item in backup.recurringPayments {
            if let existing = recurringByID[item.id] {
                existing.name = item.name
                existing.amountMinor = item.amountMinor
                existing.currency = item.currency
                existing.frequency = item.frequency
                existing.nextDate = item.nextDate
                existing.accountId = item.accountId
                existing.category = item.category
                existing.isActive = item.isActive
            } else {
                context.insert(RecurringPayment(id: item.id, name: item.name, amountMinor: item.amountMinor, currency: item.currency, frequency: item.frequency, nextDate: item.nextDate, accountId: item.accountId, category: item.category, isActive: item.isActive))
            }
        }
        try context.save()
        return backup.accounts.count + backup.transactions.count + backup.recurringPayments.count
    }
}

enum BackupError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        "This file is not a supported Ledgerly backup."
    }
}
