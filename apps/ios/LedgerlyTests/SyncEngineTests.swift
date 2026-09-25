import SwiftData
import XCTest
@testable import Ledgerly

@MainActor
final class SyncEngineTests: XCTestCase {
    private var context: ModelContext!
    private var engine: SyncEngine!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CachedAccount.self, CachedTransaction.self, SyncSetting.self, PendingMutation.self, PendingAccountMutation.self, PendingTransactionCreate.self, PendingRecurringMutation.self, PendingStockMutation.self, RecurringPayment.self, StockHolding.self, StockTrade.self, configurations: config)
        context = ModelContext(container)
        context.autosaveEnabled = false
        engine = SyncEngine(api: APIClient.shared)
    }

    // MARK: - JSONValue

    func testScreenshotPaymentParserFindsTWDPaymentAndIgnoresBalance() {
        let payment = ScreenshotPaymentParser.parse(lines: [
            "Cathay United Bank", "Available balance TWD 81,851.00", "Payment successful",
            "Louisa Coffee", "Amount TWD 165.00",
        ], currency: "TWD")
        XCTAssertEqual(payment, ScreenshotPayment(amountMinor: 16_500, title: "Louisa Coffee"))
    }

    func testScreenshotPaymentParserRequiresCurrencyOrAmountLabel() {
        XCTAssertNil(ScreenshotPaymentParser.parse(lines: ["Account", "123456789", "Sep 24"], currency: "USD"))
    }

    func testScreenshotPaymentParserDoesNotImportAnAccountBalance() {
        XCTAssertNil(ScreenshotPaymentParser.parse(lines: [
            "Account balance", "TWD 81,851.00", "Available to spend",
        ], currency: "TWD"))
    }

    func testScreenshotPaymentParserAcceptsNearbyPaymentContext() {
        XCTAssertEqual(ScreenshotPaymentParser.parse(lines: [
            "Payment successful", "TWD 165.00", "Louisa Coffee",
        ], currency: "TWD"), ScreenshotPayment(amountMinor: 16_500, title: "Louisa Coffee"))
    }

    func testJSONValueDecodesBoolBeforeNumber() throws {
        let data = Data(#"{"flag": true, "count": 3, "name": "x", "nothing": null, "list": [1, "two"]}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let object) = value else { return XCTFail("expected object") }
        XCTAssertEqual(object["flag"], .bool(true))
        XCTAssertEqual(object["count"], .number(3))
        XCTAssertEqual(object["name"], .string("x"))
        XCTAssertEqual(object["nothing"], .null)
        XCTAssertEqual(object["list"], .array([.number(1), .string("two")]))
    }

    func testJSONValueRoundTrips() throws {
        let original = JSONValue.object(["a": .number(1.5), "b": .bool(false), "c": .null])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - DTO decoding (Docker API contract)

    func testDecodesSyncResponseFromAPIShape() throws {
        let payload = """
        {"cursor":"42","changes":[{"sequence":41,"entity":"transaction","entityId":"11111111-1111-1111-1111-111111111111","action":"upsert","value":{"id":"11111111-1111-1111-1111-111111111111","accountId":"22222222-2222-2222-2222-222222222222","description":"Coffee","amount":{"amountMinor":-450,"currency":"USD"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"category":"Food","updatedAt":"2026-09-21T10:00:00.000Z"}}],"acceptedMutationIds":[]}
        """
        let response = try JSONDecoder().decode(SyncResponse.self, from: Data(payload.utf8))
        XCTAssertEqual(response.cursor, "42")
        XCTAssertEqual(response.changes.count, 1)
        XCTAssertEqual(response.changes[0].sequence, 41)
        XCTAssertTrue(response.acceptedMutationIds.isEmpty)
    }

    func testDecodesAccountAndTransactionDTO() throws {
        let accountJSON = """
        {"id":"a1","name":"Checking","institution":"Demo Bank","kind":"checking","balance":{"amountMinor":123456,"currency":"USD"},"updatedAt":"2026-09-21T10:00:00.000Z"}
        """
        let account = try JSONDecoder().decode(AccountDTO.self, from: Data(accountJSON.utf8))
        XCTAssertEqual(account.balance.amountMinor, 123456)
        XCTAssertEqual(account.kind, "checking")

        let transactionJSON = """
        {"id":"t1","accountId":"a1","description":"Coffee","amount":{"amountMinor":-450,"currency":"USD"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"updatedAt":"2026-09-21T10:00:00.000Z"}
        """
        let transaction = try JSONDecoder().decode(TransactionDTO.self, from: Data(transactionJSON.utf8))
        XCTAssertNil(transaction.category)
        XCTAssertNil(transaction.recurringPaymentId)
        XCTAssertNil(transaction.source)
    }

    func testTransactionDTOCarriesPurposeAndReimbursementMetadata() throws {
        let payload = #"{"id":"t1","accountId":"a1","description":"School supplies","amount":{"amountMinor":-450,"currency":"USD"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"category":"School","source":"manual","expensePurpose":"school","reimbursementStatus":"pending","updatedAt":"2026-09-21T10:00:00.000Z"}"#
        let transaction = try JSONDecoder().decode(TransactionDTO.self, from: Data(payload.utf8))
        XCTAssertEqual(transaction.source, "manual")
        XCTAssertEqual(transaction.expensePurpose, "school")
        XCTAssertEqual(transaction.reimbursementStatus, "pending")
    }

    // MARK: - Cache application

    private func change(_ sequence: Int, entity: String, id: String, value: String?) -> SyncChange {
        let valueJSON = value.map { try! JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        return SyncChange(sequence: sequence, entity: entity, entityId: id, action: value == nil ? "delete" : "upsert", value: valueJSON)
    }

    func testApplyUpsertsAccountAndTransaction() throws {
        try engine.apply([change(5, entity: "account", id: "acc-1", value: #"{"id":"acc-1","name":"Checking","institution":"Demo Bank","kind":"checking","balance":{"amountMinor":50000,"currency":"USD"},"updatedAt":"2026-09-21T10:00:00.000Z"}"#)], context: context)
        try engine.apply([change(6, entity: "transaction", id: "txn-1", value: #"{"id":"txn-1","accountId":"acc-1","description":"Coffee","amount":{"amountMinor":-450,"currency":"USD"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"updatedAt":"2026-09-21T10:00:00.000Z"}"#)], context: context)

        let accounts = try context.fetch(FetchDescriptor<CachedAccount>())
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].name, "Checking")
        XCTAssertEqual(accounts[0].version, 5)

        let transactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions[0].title, "Coffee")
        XCTAssertEqual(transactions[0].amountMinor, -450)
        XCTAssertEqual(transactions[0].version, 6)
        XCTAssertEqual(transactions[0].bookedDate?.timeIntervalSince1970 ?? 0, 1_789_994_400, accuracy: 86_400)
    }

    func testApplyUpdateMergesIntoExistingRow() throws {
        try testApplyUpsertsAccountAndTransaction()
        try engine.apply([change(7, entity: "transaction", id: "txn-1", value: #"{"id":"txn-1","accountId":"acc-1","description":"Coffee grande","amount":{"amountMinor":-450,"currency":"USD"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"category":"Food","updatedAt":"2026-09-21T11:00:00.000Z"}"#)], context: context)

        let transactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        XCTAssertEqual(transactions.count, 1, "upsert must not duplicate rows")
        XCTAssertEqual(transactions[0].title, "Coffee grande")
        XCTAssertEqual(transactions[0].category, "Food")
        XCTAssertEqual(transactions[0].version, 7)
    }

    func testApplyDeleteRemovesRow() throws {
        try testApplyUpsertsAccountAndTransaction()
        try engine.apply([SyncChange(sequence: 8, entity: "transaction", entityId: "txn-1", action: "delete", value: nil)], context: context)
        let transactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        XCTAssertTrue(transactions.isEmpty)
    }

    func testApplyUpsertsAndDeletesRecurringBill() throws {
        try engine.apply([change(9, entity: "recurringPayment", id: "bill-1", value: #"{"id":"bill-1","name":"Rent","amountMinor":1800000,"currency":"TWD","frequency":"monthly","nextDate":0,"accountId":null,"category":"Housing","isActive":true}"#)], context: context)
        var bills = try context.fetch(FetchDescriptor<RecurringPayment>())
        XCTAssertEqual(bills.count, 1)
        XCTAssertEqual(bills[0].name, "Rent")
        XCTAssertEqual(bills[0].currency, "TWD")

        try engine.apply([SyncChange(sequence: 10, entity: "recurringPayment", entityId: "bill-1", action: "delete", value: nil)], context: context)
        bills = try context.fetch(FetchDescriptor<RecurringPayment>())
        XCTAssertTrue(bills.isEmpty)
    }

    func testApplyUpsertsStockHoldingAndTrade() throws {
        try engine.apply([change(11, entity: "stockHolding", id: "holding-1", value: #"{"id":"holding-1","symbol":"AAPL","name":"Apple","currency":"USD","quantity":2.5,"averageCostMinor":18000,"currentPriceMinor":20000,"linkedAccountId":"account-1","updatedAt":"2026-09-25T10:00:00.000Z"}"#)], context: context)
        try engine.apply([change(12, entity: "stockTrade", id: "trade-1", value: #"{"id":"trade-1","holdingId":"holding-1","symbol":"AAPL","side":"buy","currency":"USD","quantity":2.5,"priceMinor":18000,"feesMinor":100,"tradedAt":"2026-09-25T10:00:00.000Z","linkedAccountId":"account-1"}"#)], context: context)

        let holding = try XCTUnwrap(context.fetch(FetchDescriptor<StockHolding>()).first)
        XCTAssertEqual(holding.marketValueMinor, 50_000)
        XCTAssertEqual(holding.gainLossMinor, 5_000)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StockTrade>()).first?.symbol, "AAPL")
    }

    func testServerCompatibilityDetectsLegacyAndMismatchedServers() {
        let legacy = ServerConfig(registrationEnabled: true, convexUrl: "http://localhost:3210", serverVersion: nil, syncProtocolVersion: nil, minimumAppVersion: nil, latestAppVersion: nil)
        XCTAssertEqual(LedgerlyCompatibility.evaluate(legacy), .serverOutdated)
        let mismatch = ServerConfig(registrationEnabled: true, convexUrl: "http://localhost:3210", serverVersion: "0.4.0", syncProtocolVersion: 1, minimumAppVersion: "0.4.0", latestAppVersion: "0.4.0")
        XCTAssertEqual(LedgerlyCompatibility.evaluate(mismatch), .protocolMismatch(server: 1))
    }

    func testStockTradeMathLinksBuyAndSellCashCorrectly() {
        XCTAssertEqual(StockTradeMath.cashChange(side: "buy", quantity: 2.5, priceMinor: 10_00, feesMinor: 25), -2_525)
        XCTAssertEqual(StockTradeMath.cashChange(side: "sell", quantity: 2.5, priceMinor: 10_00, feesMinor: 25), 2_475)
        XCTAssertEqual(StockTradeMath.averageCost(oldQuantity: 1, oldAverageMinor: 10_00, boughtQuantity: 1, priceMinor: 12_00, feesMinor: 0), 11_00)
    }

    func testAddingMoneyCreatesGreenTransactionAndUpdatesBalance() throws {
        let account = CachedAccount(name: "Cash", institution: "Wallet", kind: "cash", amountMinor: 500_00, currency: "TWD")
        context.insert(account)
        AccountActionService.record(amountMinor: 200_00, description: "Cash deposit", category: "Deposit", date: Date(), direction: .moneyIn, account: account, context: context)

        XCTAssertEqual(account.amountMinor, 700_00)
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<CachedTransaction>()).first)
        XCTAssertEqual(transaction.amountMinor, 200_00)
        XCTAssertEqual(transaction.source, "manual")
    }

    func testTransferMovesMoneyAndCreatesBothSides() throws {
        let source = CachedAccount(name: "Cash", institution: "Wallet", kind: "cash", amountMinor: 500_00, currency: "TWD")
        let destination = CachedAccount(name: "Checking", institution: "Bank", kind: "checking", amountMinor: 1_000_00, currency: "TWD")
        context.insert(source); context.insert(destination)
        AccountActionService.transfer(amountMinor: 100_00, description: "Move cash", date: Date(), source: source, destination: destination, context: context)

        XCTAssertEqual(source.amountMinor, 400_00)
        XCTAssertEqual(destination.amountMinor, 1_100_00)
        let transactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        XCTAssertEqual(transactions.map(\.amountMinor).sorted(), [-100_00, 100_00])
        XCTAssertTrue(transactions.allSatisfy { $0.category == "Transfer" && $0.source == "transfer" })
        let outgoing = try XCTUnwrap(transactions.first { $0.transferDirection == "outgoing" })
        let incoming = try XCTUnwrap(transactions.first { $0.transferDirection == "incoming" })
        XCTAssertEqual(outgoing.transferAccountId, destination.id)
        XCTAssertEqual(incoming.transferAccountId, source.id)
        XCTAssertEqual(outgoing.transferId, incoming.transferId)
    }

    // MARK: - Recurring payment matching

    func testRecurringMatcherAutoLinksExactMerchantAmountAndAccount() throws {
        let account = CachedAccount(name: "Checking", institution: "Test Bank", kind: "checking", amountMinor: 50_000, currency: "TWD")
        context.insert(account)
        let transaction = transaction(title: "Netflix.com", amountMinor: -390_00, currency: "TWD", accountID: account.id, category: "Entertainment")
        let bill = RecurringPayment(name: "Netflix", amountMinor: 390_00, currency: "TWD", frequency: "monthly", nextDate: Date(), accountId: account.id, category: "Entertainment")
        context.insert(transaction)
        context.insert(bill)

        XCTAssertTrue(autoLinkRecurringPayment(transaction, payments: [bill], context: context))
        XCTAssertEqual(transaction.recurringPaymentId, bill.id)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingTransactionCreate>()), 1)
    }

    func testRecurringMatcherKeepsAmountOnlyMatchAsSuggestion() {
        let transaction = transaction(title: "Neighborhood market", amountMinor: -499_00, currency: "TWD", accountID: "account-1", category: "Groceries")
        let bill = RecurringPayment(name: "Video service", amountMinor: 499_00, currency: "TWD", frequency: "monthly", nextDate: Date(), accountId: nil, category: "Entertainment")

        let match = RecurringPaymentMatcher.bestMatch(for: transaction, payments: [bill])
        XCTAssertEqual(match?.payment.id, bill.id)
        XCTAssertFalse(match?.shouldAutoLink ?? true)
    }

    func testRecurringMatcherRejectsWrongCurrencyAndAccount() {
        let transaction = transaction(title: "Netflix", amountMinor: -390_00, currency: "TWD", accountID: "account-1", category: "Entertainment")
        let wrongCurrency = RecurringPayment(name: "Netflix", amountMinor: 390_00, currency: "USD", frequency: "monthly", nextDate: Date(), accountId: "account-1", category: "Entertainment")
        let wrongAccount = RecurringPayment(name: "Netflix", amountMinor: 390_00, currency: "TWD", frequency: "monthly", nextDate: Date(), accountId: "account-2", category: "Entertainment")

        XCTAssertNil(RecurringPaymentMatcher.bestMatch(for: transaction, payments: [wrongCurrency, wrongAccount]))
    }

    func testRecurringMatcherNeverAutoLinksIncome() {
        let transaction = transaction(title: "Monthly salary", amountMinor: 68_000_00, currency: "TWD", accountID: "account-1", category: "Income")
        let bill = RecurringPayment(name: "Monthly salary", amountMinor: 68_000_00, currency: "TWD", frequency: "monthly", nextDate: Date(), accountId: "account-1", category: "Income")

        XCTAssertFalse(autoLinkRecurringPayment(transaction, payments: [bill], context: context))
        XCTAssertNil(transaction.recurringPaymentId)
    }

    func testRecurringMatcherHandlesMinimumIntegerAmount() {
        let transaction = transaction(title: "Imported payment", amountMinor: Int.min, currency: "TWD", accountID: "account-1", category: "Bills")
        let bill = RecurringPayment(name: "Imported payment", amountMinor: 599_00, currency: "TWD", frequency: "monthly", nextDate: Date(), accountId: "account-1", category: "Bills")

        XCTAssertNotNil(RecurringPaymentMatcher.bestMatch(for: transaction, payments: [bill]))
    }

    // MARK: - Reviewed merging and reimbursements

    func testMergeMatcherFindsManualAndImportedDuplicate() {
        let manual = transaction(title: "Cloud subscription", amountMinor: -499_00, currency: "TWD", accountID: "account-1", category: "Subscriptions", source: "manual")
        let imported = transaction(title: "CLOUD AUTOMATION", amountMinor: -499_00, currency: "TWD", accountID: "account-1", category: nil, source: "automation")
        let candidate = TransactionMerger.pair(manual, imported)
        XCTAssertEqual(candidate?.manual.id, manual.id)
        XCTAssertEqual(candidate?.imported.id, imported.id)
    }

    func testMergeMatcherRejectsWrongAccountAndDistantDate() {
        let manual = transaction(title: "Cloud", amountMinor: -499_00, currency: "TWD", accountID: "account-1", category: nil, source: "manual")
        let wrongAccount = transaction(title: "Cloud", amountMinor: -499_00, currency: "TWD", accountID: "account-2", category: nil, source: "automation")
        XCTAssertNil(TransactionMerger.pair(manual, wrongAccount))

        let distant = transaction(title: "Cloud", amountMinor: -499_00, currency: "TWD", accountID: "account-1", category: nil, source: "automation")
        distant.bookedAt = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-5 * 24 * 60 * 60))
        XCTAssertNil(TransactionMerger.pair(manual, distant))
    }

    func testReviewedMergePreservesImportedRecordAndManualMetadata() throws {
        let manual = transaction(title: "Cloud", amountMinor: -499_00, currency: "TWD", accountID: "account-1", category: "Subscriptions", source: "manual")
        manual.expensePurpose = "school"
        let imported = transaction(title: "Cloud provider detail", amountMinor: -499_00, currency: "TWD", accountID: "account-1", category: nil, source: "automation")
        context.insert(manual); context.insert(imported)
        let candidate = try XCTUnwrap(TransactionMerger.pair(manual, imported))
        TransactionMerger.merge(candidate, context: context)

        let remaining = try context.fetch(FetchDescriptor<CachedTransaction>())
        XCTAssertEqual(remaining.map(\.id), [imported.id])
        XCTAssertEqual(remaining.first?.category, "Subscriptions")
        XCTAssertEqual(remaining.first?.expensePurpose, "school")
    }

    func testReimbursementCreatesGreenLinkedIncomeAndUpdatesBalance() throws {
        let account = CachedAccount(name: "Checking", institution: "Bank", kind: "checking", amountMinor: 1_000_00, currency: "TWD")
        let expense = transaction(title: "School supplies", amountMinor: -500_00, currency: "TWD", accountID: account.id, category: "School", source: "manual")
        expense.expensePurpose = "school"
        expense.reimbursementStatus = "pending"
        context.insert(account); context.insert(expense)

        let reimbursement = ReimbursementService.reimburse(expense, into: account, context: context)
        XCTAssertEqual(reimbursement.amountMinor, 500_00)
        XCTAssertEqual(reimbursement.source, "reimbursement")
        XCTAssertEqual(reimbursement.reimbursementTransactionId, expense.id)
        XCTAssertEqual(expense.reimbursementStatus, "reimbursed")
        XCTAssertEqual(expense.reimbursementTransactionId, reimbursement.id)
        XCTAssertEqual(account.amountMinor, 1_500_00)
    }

    // MARK: - Cursor

    func testSaveCursorInsertsThenUpdates() throws {
        engine.saveCursor("10", settings: [], context: context)
        try context.save()
        var settings = try context.fetch(FetchDescriptor<SyncSetting>())
        XCTAssertEqual(settings.first?.value, "10")

        engine.saveCursor("11", settings: settings, context: context)
        try context.save()
        settings = try context.fetch(FetchDescriptor<SyncSetting>())
        XCTAssertEqual(settings.count, 1, "cursor setting must be updated, not duplicated")
        XCTAssertEqual(settings.first?.value, "11")
    }

    // MARK: - Outbox operations

    func testPendingMutationEncodesAPIOperation() throws {
        let mutation = PendingMutation(entityId: "11111111-1111-1111-1111-111111111111", action: "upsert", newDescription: "Renamed", newCategory: "Food", baseVersion: 3)
        let body = try JSONEncoder().encode([mutation.operation])
        let json = String(data: body, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("\"baseVersion\":3"))
        XCTAssertTrue(json.contains("\"entity\":\"transaction\""))
        XCTAssertTrue(json.contains("\"description\":\"Renamed\""))
        XCTAssertTrue(json.contains("\"category\":\"Food\""))
        XCTAssertEqual(mutation.mutationId.count, 36, "API requires UUID mutation ids")
    }

    func testPendingMutationDeleteOmitsValue() throws {
        let mutation = PendingMutation(entityId: "11111111-1111-1111-1111-111111111111", action: "delete", newDescription: nil, newCategory: nil, baseVersion: 1)
        let body = try JSONEncoder().encode(mutation.operation)
        let json = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"action\":\"delete\""))
        XCTAssertFalse(json.contains("description"))
        XCTAssertFalse(json.contains("value"))
    }

    func testOperationValueOmitsEmptyFields() throws {
        let operation = SyncOperation(mutationId: "11111111-1111-1111-1111-111111111111", action: "upsert", entityId: "22222222-2222-2222-2222-222222222222", value: .init(description: "Only title", category: nil), baseVersion: 2)
        let json = String(data: try JSONEncoder().encode(operation), encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"description\":\"Only title\""))
        XCTAssertFalse(json.contains("category"))
    }

    func testRecurringPaymentLinkAndUnlinkEncodeExplicitly() throws {
        let link = PendingMutation(
            entityId: "transaction-1", action: "upsert", newDescription: nil, newCategory: nil,
            newRecurringPaymentId: "recurring-1", updatesRecurringPayment: true, baseVersion: 1
        )
        let linkJSON = String(data: try JSONEncoder().encode(link.operation), encoding: .utf8) ?? ""
        XCTAssertTrue(linkJSON.contains(#""recurringPaymentId":"recurring-1""#))

        let unlink = PendingMutation(
            entityId: "transaction-1", action: "upsert", newDescription: nil, newCategory: nil,
            newRecurringPaymentId: nil, updatesRecurringPayment: true, baseVersion: 1
        )
        let unlinkJSON = String(data: try JSONEncoder().encode(unlink.operation), encoding: .utf8) ?? ""
        XCTAssertTrue(unlinkJSON.contains(#""recurringPaymentId":null"#))
    }

    func testBackupRoundTripIsIdempotent() throws {
        let account = CachedAccount(name: "Checking", institution: "Test Bank", kind: "checking", amountMinor: 12_345, currency: "TWD")
        context.insert(account)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        context.insert(CachedTransaction(dto: TransactionDTO(id: "transaction-1", accountId: account.id, description: "Coffee", amount: Money(amountMinor: -150, currency: "TWD"), bookedAt: timestamp, pending: false, category: "Dining", recurringPaymentId: "recurring-1", updatedAt: timestamp)))
        context.insert(RecurringPayment(id: "recurring-1", name: "Rent", amountMinor: 18_000_00, currency: "TWD", frequency: "monthly", nextDate: Date(), accountId: account.id, category: "Housing"))
        try context.save()

        let backup = try LedgerlyBackupService.create(from: context)
        let destinationConfig = ModelConfiguration(isStoredInMemoryOnly: true)
        let destinationContainer = try ModelContainer(for: CachedAccount.self, CachedTransaction.self, SyncSetting.self, PendingMutation.self, PendingAccountMutation.self, PendingTransactionCreate.self, PendingRecurringMutation.self, PendingStockMutation.self, RecurringPayment.self, StockHolding.self, StockTrade.self, configurations: destinationConfig)
        let destination = ModelContext(destinationContainer)

        XCTAssertEqual(try LedgerlyBackupService.restore(backup, into: destination), 3)
        XCTAssertEqual(try LedgerlyBackupService.restore(backup, into: destination), 3)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<CachedAccount>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<CachedTransaction>()), 1)
        XCTAssertEqual(try destination.fetchCount(FetchDescriptor<RecurringPayment>()), 1)
        XCTAssertEqual(try destination.fetch(FetchDescriptor<CachedTransaction>()).first?.recurringPaymentId, "recurring-1")
    }


    func testBackupIncludesStockPortfolio() throws {
        let holding = StockHolding(id: "holding-1", symbol: "TSM", name: "TSMC", quantity: 10, averageCostMinor: 90_00, currentPriceMinor: 110_00, currency: "USD", linkedAccountId: nil)
        context.insert(holding)
        context.insert(StockTrade(id: "trade-1", holdingId: holding.id, symbol: "TSM", side: "buy", quantity: 10, priceMinor: 90_00, feesMinor: 0, currency: "USD", tradedAt: ISO8601DateFormatter().string(from: Date()), linkedAccountId: nil))
        try context.save()
        let backup = try LedgerlyBackupService.create(from: context)
        XCTAssertEqual(backup.stockHoldings?.first?.symbol, "TSM")
        XCTAssertEqual(backup.stockTrades?.first?.side, "buy")
    }

    private func transaction(title: String, amountMinor: Int, currency: String, accountID: String, category: String?, source: String? = nil) -> CachedTransaction {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(), accountId: accountID, description: title,
            amount: Money(amountMinor: amountMinor, currency: currency), bookedAt: timestamp,
            pending: false, category: category, source: source, updatedAt: timestamp
        ))
    }
}
