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
        let source: String?
        let expensePurpose: String?
        let reimbursementStatus: String?
        let reimbursementTransactionId: String?
        let transferId: String?
        let transferAccountId: String?
        let transferDirection: String?
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

    struct Holding: Codable {
        let id, symbol, name, currency: String
        let quantity: Double
        let averageCostMinor, currentPriceMinor: Int
        let linkedAccountId: String?
        let updatedAt: String
    }

    struct Trade: Codable {
        let id, holdingId, symbol, side, currency: String
        let quantity: Double
        let priceMinor, feesMinor: Int
        let tradedAt: String
        let linkedAccountId: String?
    }

    let format: String
    let version: Int
    let exportedAt: Date
    let accounts: [Account]
    let transactions: [Transaction]
    let recurringPayments: [Recurring]
    let stockHoldings: [Holding]?
    let stockTrades: [Trade]?
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
            LedgerlyBackup.Transaction(id: $0.id, accountId: $0.accountId, title: $0.title, amountMinor: $0.amountMinor, currency: $0.currency, bookedAt: $0.bookedAt, pending: $0.pending, category: $0.category, recurringPaymentId: $0.recurringPaymentId, source: $0.source, expensePurpose: $0.expensePurpose, reimbursementStatus: $0.reimbursementStatus, reimbursementTransactionId: $0.reimbursementTransactionId, transferId: $0.transferId, transferAccountId: $0.transferAccountId, transferDirection: $0.transferDirection, version: $0.version, updatedAt: $0.updatedAt)
        }
        let recurring = try context.fetch(FetchDescriptor<RecurringPayment>()).map {
            LedgerlyBackup.Recurring(id: $0.id, name: $0.name, amountMinor: $0.amountMinor, currency: $0.currency, frequency: $0.frequency, nextDate: $0.nextDate, accountId: $0.accountId, category: $0.category, isActive: $0.isActive)
        }
        let holdings = try context.fetch(FetchDescriptor<StockHolding>()).map {
            LedgerlyBackup.Holding(id: $0.id, symbol: $0.symbol, name: $0.name, currency: $0.currency, quantity: $0.quantity, averageCostMinor: $0.averageCostMinor, currentPriceMinor: $0.currentPriceMinor, linkedAccountId: $0.linkedAccountId, updatedAt: $0.updatedAt)
        }
        let trades = try context.fetch(FetchDescriptor<StockTrade>()).map {
            LedgerlyBackup.Trade(id: $0.id, holdingId: $0.holdingId, symbol: $0.symbol, side: $0.side, currency: $0.currency, quantity: $0.quantity, priceMinor: $0.priceMinor, feesMinor: $0.feesMinor, tradedAt: $0.tradedAt, linkedAccountId: $0.linkedAccountId)
        }
        return LedgerlyBackup(format: "com.ledgerly.backup", version: 1, exportedAt: Date(), accounts: accounts, transactions: transactions, recurringPayments: recurring, stockHoldings: holdings, stockTrades: trades)
    }

    @discardableResult
    @MainActor
    static func restore(_ backup: LedgerlyBackup, into context: ModelContext) throws -> Int {
        guard backup.format == "com.ledgerly.backup", backup.version == 1 else { throw BackupError.unsupportedFormat }

        let currentAccounts = try context.fetch(FetchDescriptor<CachedAccount>())
        let currentTransactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        let currentRecurring = try context.fetch(FetchDescriptor<RecurringPayment>())
        let currentHoldings = try context.fetch(FetchDescriptor<StockHolding>())
        let currentTrades = try context.fetch(FetchDescriptor<StockTrade>())
        let accountsByID = Dictionary(uniqueKeysWithValues: currentAccounts.map { ($0.id, $0) })
        let transactionsByID = Dictionary(uniqueKeysWithValues: currentTransactions.map { ($0.id, $0) })
        let recurringByID = Dictionary(uniqueKeysWithValues: currentRecurring.map { ($0.id, $0) })
        let holdingsByID = Dictionary(uniqueKeysWithValues: currentHoldings.map { ($0.id, $0) })
        let tradesByID = Dictionary(uniqueKeysWithValues: currentTrades.map { ($0.id, $0) })

        for item in backup.accounts {
            let dto = AccountDTO(id: item.id, name: item.name, institution: item.institution, kind: item.kind, balance: Money(amountMinor: item.amountMinor, currency: item.currency), updatedAt: item.updatedAt)
            if let existing = accountsByID[item.id] { existing.apply(dto, version: item.version) }
            else { context.insert(CachedAccount(dto: dto, initialVersion: item.version)) }
        }
        for item in backup.transactions {
            let dto = TransactionDTO(id: item.id, accountId: item.accountId, description: item.title, amount: Money(amountMinor: item.amountMinor, currency: item.currency), bookedAt: item.bookedAt, pending: item.pending, category: item.category, recurringPaymentId: item.recurringPaymentId, source: item.source, expensePurpose: item.expensePurpose, reimbursementStatus: item.reimbursementStatus, reimbursementTransactionId: item.reimbursementTransactionId, transferId: item.transferId, transferAccountId: item.transferAccountId, transferDirection: item.transferDirection, updatedAt: item.updatedAt)
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
        for item in backup.stockHoldings ?? [] {
            if let existing = holdingsByID[item.id] {
                existing.symbol = item.symbol; existing.name = item.name; existing.quantity = item.quantity
                existing.averageCostMinor = item.averageCostMinor; existing.currentPriceMinor = item.currentPriceMinor
                existing.currency = item.currency; existing.linkedAccountId = item.linkedAccountId; existing.updatedAt = item.updatedAt
            } else {
                context.insert(StockHolding(id: item.id, symbol: item.symbol, name: item.name, quantity: item.quantity, averageCostMinor: item.averageCostMinor, currentPriceMinor: item.currentPriceMinor, currency: item.currency, linkedAccountId: item.linkedAccountId, updatedAt: item.updatedAt))
            }
        }
        for item in backup.stockTrades ?? [] where tradesByID[item.id] == nil {
            context.insert(StockTrade(id: item.id, holdingId: item.holdingId, symbol: item.symbol, side: item.side, quantity: item.quantity, priceMinor: item.priceMinor, feesMinor: item.feesMinor, currency: item.currency, tradedAt: item.tradedAt, linkedAccountId: item.linkedAccountId))
        }
        try context.save()
        return backup.accounts.count + backup.transactions.count + backup.recurringPayments.count + (backup.stockHoldings?.count ?? 0) + (backup.stockTrades?.count ?? 0)
    }
}

enum BackupError: LocalizedError {
    case unsupportedFormat

    var errorDescription: String? {
        "This file is not a supported Ledgerly backup."
    }
}
