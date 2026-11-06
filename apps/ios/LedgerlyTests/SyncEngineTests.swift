import SwiftData
import UIKit
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

    func testPartialAccountChangePatchesCachedAccountInsteadOfFailingSync() throws {
        let account = CachedAccount(name: "EasyCard", institution: "EasyCard", kind: "prepaid", amountMinor: 10000, currency: "TWD")
        context.insert(account)
        let partial = JSONValue.object([
            "id": .string(account.id),
            "balance": .object(["amountMinor": .number(5000), "currency": .string("TWD")]),
            "updatedAt": .string("2026-11-06T00:00:00Z"),
        ])
        let unknown = JSONValue.object(["id": .string("missing"), "balance": .object(["amountMinor": .number(1), "currency": .string("TWD")]), "updatedAt": .string("2026-11-06T00:00:00Z")])
        try engine.apply([
            SyncChange(sequence: 1, entity: "account", entityId: account.id, action: "upsert", value: partial),
            SyncChange(sequence: 2, entity: "account", entityId: "missing", action: "upsert", value: unknown),
        ], context: context)
        XCTAssertEqual(account.name, "EasyCard")
        XCTAssertEqual(account.amountMinor, 5000)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedAccount>()), 1)
    }

    func testMalformedRecordDoesNotBlockLaterChanges() throws {
        let account = CachedAccount(name: "Bank", institution: "Bank", kind: "checking", amountMinor: 100, currency: "TWD")
        context.insert(account)
        try engine.apply([
            SyncChange(sequence: 1, entity: "transaction", entityId: "broken", action: "upsert", value: .object(["id": .string("broken")])),
            SyncChange(sequence: 2, entity: "account", entityId: account.id, action: "delete", value: nil),
        ], context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedAccount>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedTransaction>()), 0)
    }

    func testDeletingImportedTransactionDoesNotInventAccountBalance() throws {
        let account = CachedAccount(name: "Bank", institution: "Bank", kind: "checking", amountMinor: 100000, currency: "TWD")
        context.insert(account)
        let transaction = CachedTransaction(dto: TransactionDTO(id: "bank-import", accountId: account.id, description: "Bank expense", amount: Money(amountMinor: -20000, currency: "TWD"), bookedAt: "2026-01-31T00:00:00Z", pending: false, category: nil, updatedAt: "2026-01-31T00:00:00Z"))
        context.insert(transaction)
        try AccountActionService.delete(transaction, context: context)
        XCTAssertEqual(account.amountMinor, 100000)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingAccountMutation>()), 0)
    }

    func testSettledForeignPurchaseRetainsZeroAppliedBalanceImpact() throws {
        let account = CachedAccount(name: "Bank", institution: "Bank", kind: "checking", amountMinor: 100000, currency: "TWD")
        context.insert(account)
        AccountActionService.record(amountMinor: 1500, description: "Netflix", category: "Entertainment", date: Date(), direction: .moneyOut, account: account, context: context, purchaseCurrency: "USD")
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<CachedTransaction>()).first)
        XCTAssertEqual(transaction.balanceImpactMinor, 0)
        let dto = TransactionDTO(id: transaction.id, accountId: account.id, description: "Netflix", amount: Money(amountMinor: -48000, currency: "TWD"), bookedAt: transaction.bookedAt, pending: false, category: nil, source: "manual", updatedAt: transaction.updatedAt)
        transaction.apply(dto, version: 2)
        try AccountActionService.delete(transaction, context: context)
        XCTAssertEqual(account.amountMinor, 100000)
    }

    func testRemovingSubscriptionEstimatesPreservesActualPaymentsAndClearsTheirCreates() throws {
        let bill = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: Date(), accountId: "cash", category: "Entertainment")
        context.insert(bill)
        for source in ["subscription", "manual"] {
            let transaction = CachedTransaction(dto: TransactionDTO(id: source, accountId: "cash", description: "Netflix", amount: Money(amountMinor: source == "manual" ? -1500 : 0, currency: "USD"), bookedAt: "2026-01-31T00:00:00Z", pending: source == "subscription", category: nil, recurringPaymentId: bill.id, source: source, updatedAt: "2026-01-31T00:00:00Z"))
            context.insert(transaction)
            context.insert(PendingTransactionCreate(entityId: source))
        }
        try SubscriptionScheduler.removeEstimates(paymentID: bill.id, context: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedTransaction>()).map(\.id), ["manual"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PendingTransactionCreate>()).map(\.entityId), ["manual"])
        XCTAssertTrue(try context.fetch(FetchDescriptor<PendingMutation>()).contains { $0.entityId == "subscription" && $0.action == "delete" })
    }

    func testAutomaticSubscriptionAmbiguityUsesSameStrictCandidatesAsServer() {
        let named = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: Date(), accountId: "cash", category: "Entertainment")
        let unassigned = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: Date(), accountId: nil, category: "Entertainment")
        XCTAssertTrue(RecurringPaymentMatcher.bestMatch(title: "Netflix", amountMinor: -1500, currency: "USD", accountID: "cash", category: "Entertainment", payments: [named, unassigned])?.shouldAutoLink ?? false)
        let other = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: Date(), accountId: "cash", category: "Shopping")
        XCTAssertFalse(RecurringPaymentMatcher.bestMatch(title: "Netflix", amountMinor: -1500, currency: "USD", accountID: "cash", category: "Entertainment", payments: [named, other])?.shouldAutoLink ?? true)
    }

    func testAccountDeletionRemovesAllHistoryBeyondDisplayedPageAndPendingCreates() throws {
        for index in 0..<501 {
            let transaction = CachedTransaction(dto: TransactionDTO(id: "history-\(index)", accountId: "deleted-account", description: "Entry", amount: Money(amountMinor: -100, currency: "TWD"), bookedAt: "2026-01-01T00:00:00Z", pending: false, category: nil, updatedAt: "2026-01-01T00:00:00Z"))
            context.insert(transaction)
            context.insert(PendingTransactionCreate(entityId: transaction.id))
        }
        context.insert(CachedTransaction(dto: TransactionDTO(id: "retained", accountId: "other", description: "Keep", amount: Money(amountMinor: -100, currency: "TWD"), bookedAt: "2026-01-01T00:00:00Z", pending: false, category: nil, updatedAt: "2026-01-01T00:00:00Z")))
        try AccountActionService.removeAccountTransactions(accountID: "deleted-account", context: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<CachedTransaction>()).map(\.id), ["retained"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingTransactionCreate>()), 0)
    }

    func testSyncPullsAllChangePagesAndPersistsOneFinalCursor() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PagedSyncURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let client = APIClient(baseURL: URL(string: "https://ledgerly.test")!, session: session)
        _ = try await SyncEngine(api: client).runSync(context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedAccount>()), 501)
        let cursors = try context.fetch(FetchDescriptor<SyncSetting>()).filter { $0.key == "cursor" }
        XCTAssertEqual(cursors.count, 1)
        XCTAssertEqual(cursors.first?.value, "501")
    }

    func testExplicitServerUnlinkSurvivesMatchingAndClearedOutbox() throws {
        let bill = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: Date.distantFuture, accountId: "cash", category: "Entertainment")
        context.insert(bill)
        let value: JSONValue = .object([
            "id": .string("real"), "accountId": .string("cash"), "description": .string("Netflix.com"),
            "amount": .object(["amountMinor": .number(-1500), "currency": .string("USD")]),
            "bookedAt": .string("2026-01-31T00:00:00Z"), "pending": .bool(false),
            "category": .string("Entertainment"), "recurringPaymentId": .null,
            "updatedAt": .string("2026-01-31T00:00:00Z")
        ])
        try engine.apply([SyncChange(sequence: 1, entity: "transaction", entityId: "real", action: "upsert", value: value)], context: context)
        let transaction = try XCTUnwrap(context.fetch(FetchDescriptor<CachedTransaction>()).first)
        XCTAssertTrue(transaction.recurringPaymentUnlinked)
        XCTAssertNil(transaction.recurringPaymentId)
        try SubscriptionScheduler.generateDue(context: context)
        XCTAssertNil(transaction.recurringPaymentId)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingTransactionCreate>()), 0)
        let dto = TransactionDTO(id: "real", accountId: "cash", description: "Netflix", amount: Money(amountMinor: -1500, currency: "USD"), bookedAt: "2026-01-31T00:00:00Z", pending: false, category: nil, updatedAt: "2026-01-31T00:00:00Z")
        let data = try JSONEncoder().encode(SyncOperation.OperationValue(includesRecurringPaymentId: true, transaction: dto))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(encoded["recurringPaymentId"] is NSNull)
    }

    func testSubscriptionAutoLinkRejectsDifferentAmountEvenWithMerchantAndCategory() throws {
        let bill = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: Date(), accountId: "cash", category: "Entertainment")
        let match = RecurringPaymentMatcher.bestMatch(title: "Netflix.com", amountMinor: -999999, currency: "USD", accountID: "cash", category: "Entertainment", payments: [bill])
        XCTAssertFalse(match?.shouldAutoLink ?? true)
    }

    func testSubscriptionCalendarPreservesTimeAndFractionalSeconds() throws {
        let due = try XCTUnwrap(LedgerlyISODate.parse("2024-02-29T15:59:59.125Z"))
        for (frequency, expected) in [("monthly", "2024-03-29T15:59:59.125Z"), ("yearly", "2025-02-28T15:59:59.125Z"), ("everyTwoYears", "2026-02-28T15:59:59.125Z")] {
            let next = try XCTUnwrap(SubscriptionScheduler.nextDate(after: due, frequency: frequency, anchorDay: 29))
            XCTAssertEqual(next.timeIntervalSince1970, try XCTUnwrap(LedgerlyISODate.parse(expected)).timeIntervalSince1970, accuracy: 0.000001)
        }
        XCTAssertTrue(SubscriptionScheduler.includesPayment(try XCTUnwrap(LedgerlyISODate.parse("2024-03-15T00:00:00Z")), due: due, frequency: "monthly", anchorDay: 29))
    }

    func testRecurringMatcherDoesNotAutoLinkDifferentMerchantsWithSameAmountAndCategory() {
        let bill = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: Date(), accountId: "account", category: "Entertainment")
        let match = RecurringPaymentMatcher.bestMatch(title: "DisneyPlus.com", amountMinor: -1500, currency: "USD", accountID: "account", category: "Entertainment", payments: [bill])
        XCTAssertNotNil(match)
        XCTAssertFalse(match?.shouldAutoLink ?? true)
        XCTAssertTrue(RecurringPaymentMatcher.bestMatch(title: "Netflix.com", amountMinor: -1500, currency: "USD", accountID: "account", category: "Entertainment", payments: [bill])?.shouldAutoLink ?? false)
    }

    func testMalformedLocalSubscriptionFrequencyDoesNotQueueRepeatedUpserts() throws {
        let account = CachedAccount(name: "Cash", institution: "Manual", kind: "cash", amountMinor: 1000, currency: "TWD")
        let due = Date(timeIntervalSince1970: 1000)
        let bill = RecurringPayment(name: "Bad schedule", amountMinor: 100, currency: "TWD", frequency: "invalid", nextDate: due, accountId: account.id, category: "Bills")
        context.insert(account); context.insert(bill)
        try SubscriptionScheduler.generateDue(context: context)
        try SubscriptionScheduler.generateDue(context: context)
        XCTAssertEqual(bill.nextDate, due)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PendingRecurringMutation>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedTransaction>()), 0)
    }

    func testSubscriptionBillingWindowIncludesEarlyAndLatePaymentsButNotNextCycle() throws {
        let due = try XCTUnwrap(LedgerlyISODate.parse("2026-01-31T00:00:00+08:00"))
        for text in ["2026-01-26T00:00:00+08:00", "2026-02-05T00:00:00+08:00"] {
            let booked = try XCTUnwrap(LedgerlyISODate.parse(text))
            XCTAssertTrue(SubscriptionScheduler.includesPayment(booked, due: due, frequency: "monthly", anchorDay: 31))
        }
        let nextCycle = try XCTUnwrap(LedgerlyISODate.parse("2026-02-20T00:00:00+08:00"))
        XCTAssertFalse(SubscriptionScheduler.includesPayment(nextCycle, due: due, frequency: "monthly", anchorDay: 31))
    }

    func testEarlySubscriptionPaymentPreventsEstimateAndInvalidAnchorNormalizes() throws {
        let account = CachedAccount(name: "Cash", institution: "Manual", kind: "cash", amountMinor: 10000, currency: "TWD")
        let due = try XCTUnwrap(LedgerlyISODate.parse("2026-01-31T00:00:00+08:00"))
        let bill = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "TWD", frequency: "monthly", nextDate: due, accountId: account.id, category: "Entertainment")
        bill.scheduleAnchorDay = -1
        let real = CachedTransaction(dto: TransactionDTO(id: "early", accountId: account.id, description: "Netflix.com", amount: Money(amountMinor: -1500, currency: "TWD"), bookedAt: "2026-01-30T00:00:00+08:00", pending: false, category: "Entertainment", updatedAt: "2026-01-30T00:00:00+08:00"))
        context.insert(account); context.insert(bill); context.insert(real)
        try SubscriptionScheduler.generateDue(context: context, now: due)
        try SubscriptionScheduler.generateDue(context: context, now: due)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedTransaction>()), 1)
        XCTAssertEqual(real.recurringPaymentId, bill.id)
        XCTAssertEqual(bill.scheduleAnchorDay, 31)
        XCTAssertEqual(bill.nextDate, LedgerlyISODate.parse("2026-02-28T00:00:00+08:00"))
    }

    func testSubscriptionsGenerateOnceCatchUpAndKeepMonthEndAnchorWithoutChangingCash() throws {
        let account = CachedAccount(name: "Cash", institution: "Manual", kind: "cash", amountMinor: 10000, currency: "TWD")
        let due = try XCTUnwrap(LedgerlyISODate.parse("2026-01-31T00:00:00+08:00"))
        let now = try XCTUnwrap(LedgerlyISODate.parse("2026-02-28T01:00:00+08:00"))
        let bill = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: due, accountId: account.id, category: "Entertainment")
        context.insert(account); context.insert(bill)
        try SubscriptionScheduler.generateDue(context: context, now: now)
        try SubscriptionScheduler.generateDue(context: context, now: now)
        let entries = try context.fetch(FetchDescriptor<CachedTransaction>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.allSatisfy { $0.recurringPaymentId == bill.id && $0.source == "subscription" && $0.pending && $0.presentedAmountMinor == -1500 })
        XCTAssertEqual(account.amountMinor, 10000)
        XCTAssertEqual(bill.nextDate, LedgerlyISODate.parse("2026-03-31T00:00:00+08:00"))
        bill.isActive = false
        try SubscriptionScheduler.generateDue(context: context, now: now.addingTimeInterval(365 * 86400))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedTransaction>()), 2)
    }

    func testActualSubscriptionPaymentReplacesExpectedRecord() throws {
        let account = CachedAccount(name: "Cash", institution: "Manual", kind: "cash", amountMinor: 10000, currency: "TWD")
        let now = try XCTUnwrap(LedgerlyISODate.parse("2026-10-29T00:00:00Z"))
        let bill = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "TWD", frequency: "monthly", nextDate: now, accountId: account.id, category: "Entertainment")
        context.insert(account); context.insert(bill)
        try SubscriptionScheduler.generateDue(context: context, now: now)
        let real = CachedTransaction(dto: TransactionDTO(id: "actual-payment", accountId: account.id, description: "Netflix.com", amount: Money(amountMinor: -1500, currency: "TWD"), bookedAt: "2026-10-29T01:00:00Z", pending: false, category: "Entertainment", updatedAt: "2026-10-29T01:00:00Z"))
        context.insert(real)
        XCTAssertTrue(autoLinkRecurringPayment(real, payments: [bill], context: context))
        try context.save()
        let entries = try context.fetch(FetchDescriptor<CachedTransaction>())
        XCTAssertEqual(entries.map(\.id), ["actual-payment"])
        XCTAssertEqual(real.recurringPaymentId, bill.id)
        try SubscriptionScheduler.generateDue(context: context, now: now)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedTransaction>()), 1)
    }

    func testDeletedTransactionOutboxCleanupPreservesOtherRecordsAndDeletes() throws {
        context.insert(PendingTransactionCreate(entityId: "deleted"))
        context.insert(PendingTransactionCreate(entityId: "retained"))
        context.insert(PendingMutation(entityId: "deleted", action: "upsert", newDescription: "Old edit", newCategory: nil, baseVersion: 0))
        context.insert(PendingMutation(entityId: "deleted", action: "delete", newDescription: nil, newCategory: nil, baseVersion: 0))
        context.insert(PendingMutation(entityId: "retained", action: "upsert", newDescription: "Keep", newCategory: nil, baseVersion: 0))
        try context.save()
        try AccountActionService.removePendingTransactionWrites(ids: ["deleted"], context: context)
        try context.save()
        let creates = try context.fetch(FetchDescriptor<PendingTransactionCreate>())
        XCTAssertEqual(creates.map(\.entityId), ["retained"])
        let mutations = try context.fetch(FetchDescriptor<PendingMutation>())
        XCTAssertEqual(mutations.count, 2)
        XCTAssertTrue(mutations.contains { $0.entityId == "deleted" && $0.action == "delete" })
        XCTAssertTrue(mutations.contains { $0.entityId == "retained" && $0.action == "upsert" })
    }

    func testMoneyInputRejectsMalformedAndOverflowingAmounts() {
        for input in ["1.2.3", "abc", "12abc", "1.234", "", "999999999999999999999999"] {
            XCTAssertNil(MoneyInput.minorUnits(input), input)
        }
        XCTAssertEqual(MoneyInput.minorUnits("1.20"), 120)
        XCTAssertEqual(MoneyInput.minorUnits("1,20"), 120)
        XCTAssertEqual(MoneyInput.minorUnits("-5"), -500)
        XCTAssertEqual(MoneyInput.minorUnits("0"), 0)
    }

    func testDeletingEitherTransferLegReversesBothAccountsAndQueuesBothDeletes() throws {
        for deleteIncoming in [false, true] {
            let source = CachedAccount(name: "Source", institution: "Manual", kind: "checking", amountMinor: 10000, currency: "TWD")
            let destination = CachedAccount(name: "Destination", institution: "Manual", kind: "cash", amountMinor: 5000, currency: "TWD")
            context.insert(source)
            context.insert(destination)
            AccountActionService.transfer(amountMinor: 500, description: "Transfer", date: Date(), source: source, destination: destination, context: context)
            let entries = try context.fetch(FetchDescriptor<CachedTransaction>())
            let entry = try XCTUnwrap(entries.first(where: { $0.accountId == (deleteIncoming ? destination.id : source.id) }))
            let entryIDs = Set(entries.map(\.id))
            try AccountActionService.delete(entry, context: context)
            XCTAssertEqual(source.amountMinor, 10000)
            XCTAssertEqual(destination.amountMinor, 5000)
            XCTAssertTrue(try context.fetch(FetchDescriptor<CachedTransaction>()).isEmpty)
            XCTAssertTrue(try context.fetch(FetchDescriptor<PendingTransactionCreate>()).isEmpty)
            let deletedIDs = Set(try context.fetch(FetchDescriptor<PendingMutation>()).filter { $0.action == "delete" }.map(\.entityId))
            XCTAssertTrue(entryIDs.isSubset(of: deletedIDs))
        }
    }

    func testAccountIconsAreValidAndMatchAccountMeaning() {
        let expected = [
            "checking": "building.columns.fill",
            "savings": "banknote.fill",
            "credit": "creditcard.fill",
            "sharedCredit": "creditcard.fill",
            "investment": "chart.line.uptrend.xyaxis",
            "cash": "wallet.bifold.fill",
        ]

        for (kind, symbol) in expected {
            XCTAssertEqual(AppIcon.account(kind: kind), symbol)
            XCTAssertNotNil(UIImage(systemName: symbol), "Missing SF Symbol: \(symbol)")
        }
    }

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
        {"id":"a1","name":"Checking","institution":"Test Bank","kind":"checking","balance":{"amountMinor":123456,"currency":"USD"},"updatedAt":"2026-09-21T10:00:00.000Z"}
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

    func testTransactionDTOCarriesForeignPurchaseAndSettlementAmounts() throws {
        let payload = #"{"id":"t1","accountId":"a1","description":"Japan purchase","amount":{"amountMinor":-21500,"currency":"TWD"},"originalAmount":{"amountMinor":-100000,"currency":"JPY"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"updatedAt":"2026-09-21T10:00:00.000Z"}"#
        let transaction = try JSONDecoder().decode(TransactionDTO.self, from: Data(payload.utf8))
        XCTAssertEqual(transaction.amount, Money(amountMinor: -21_500, currency: "TWD"))
        XCTAssertEqual(transaction.originalAmount, Money(amountMinor: -100_000, currency: "JPY"))
    }

    // MARK: - Cache application

    private func change(_ sequence: Int, entity: String, id: String, value: String?) -> SyncChange {
        let valueJSON = value.map { try! JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        return SyncChange(sequence: sequence, entity: entity, entityId: id, action: value == nil ? "delete" : "upsert", value: valueJSON)
    }

    func testApplyUpsertsAccountAndTransaction() throws {
        try engine.apply([change(5, entity: "account", id: "acc-1", value: #"{"id":"acc-1","name":"Checking","institution":"Test Bank","kind":"checking","balance":{"amountMinor":50000,"currency":"USD"},"updatedAt":"2026-09-21T10:00:00.000Z"}"#)], context: context)
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

    func testApplyHandlesFullSyncPageInOneBatch() throws {
        let changes = (1...500).map { index in
            change(
                index,
                entity: "transaction",
                id: "batch-\(index)",
                value: #"{"id":"batch-\#(index)","accountId":"account-1","description":"Transaction \#(index)","amount":{"amountMinor":-450,"currency":"USD"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"updatedAt":"2026-09-21T10:00:00.000Z"}"#
            )
        }

        try engine.apply(changes, context: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CachedTransaction>()), 500)
    }

    func testISODateParserSupportsFractionalAndWholeSeconds() {
        XCTAssertNotNil(LedgerlyISODate.parse("2026-09-21T10:00:00.000Z"))
        XCTAssertNotNil(LedgerlyISODate.parse("2026-09-21T10:00:00Z"))
        XCTAssertNil(LedgerlyISODate.parse("not-a-date"))
    }

    func testApplyUpdateMergesIntoExistingRow() throws {
        try testApplyUpsertsAccountAndTransaction()
        try engine.apply([change(7, entity: "transaction", id: "txn-1", value: #"{"id":"txn-1","accountId":"acc-1","description":"Coffee grande","amount":{"amountMinor":-450,"currency":"USD"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"category":"Food","categoryUserEdited":true,"updatedAt":"2026-09-21T11:00:00.000Z"}"#)], context: context)

        let transactions = try context.fetch(FetchDescriptor<CachedTransaction>())
        XCTAssertEqual(transactions.count, 1, "upsert must not duplicate rows")
        XCTAssertEqual(transactions[0].title, "Coffee grande")
        XCTAssertEqual(transactions[0].category, "Food")
        XCTAssertTrue(transactions[0].categoryUserEdited)
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

    func testNetWorthIncludesStockHoldingsAndExcludesTrackedCards() {
        let cash = CachedAccount(dto: AccountDTO(id: "cash", name: "Cash", institution: "Manual", kind: "cash", balance: Money(amountMinor: 10_000, currency: "USD"), updatedAt: "2026-09-25T10:00:00.000Z"))
        let trackedCard = CachedAccount(dto: AccountDTO(id: "card", name: "Dad's card", institution: "Manual", kind: "sharedCredit", balance: Money(amountMinor: -2_000, currency: "USD"), updatedAt: "2026-09-25T10:00:00.000Z"))
        let holding = StockHolding(symbol: "AAPL", name: "Apple", quantity: 2, averageCostMinor: 4_000, currentPriceMinor: 5_000, currency: "USD", linkedAccountId: cash.id)

        let totals = NetWorthCalculator.totals(accounts: [cash, trackedCard], holdings: [holding])

        XCTAssertEqual(totals["USD"], 20_000)
    }

    func testEveryTwoYearsFrequencyHasReadableLabel() {
        let payment = RecurringPayment(name: "Domain", amountMinor: 3_000, currency: "USD", frequency: "everyTwoYears", nextDate: Date(), accountId: nil, category: "Domains")
        XCTAssertEqual(payment.frequencyLabel, "Every 2 years")
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

    func testForeignCardPurchaseWaitsForBankSettlementWithoutChangingBalance() throws {
        let account = CachedAccount(name: "Debit card", institution: "Bank", kind: "checking", amountMinor: 10_000_00, currency: "TWD")
        context.insert(account)

        AccountActionService.record(
            amountMinor: 1_500_00,
            description: "Japan purchase",
            category: "Shopping",
            date: Date(),
            direction: .moneyOut,
            account: account,
            context: context,
            purchaseCurrency: "JPY"
        )

        let recorded = try XCTUnwrap(context.fetch(FetchDescriptor<CachedTransaction>()).first)
        XCTAssertEqual(account.amountMinor, 10_000_00)
        XCTAssertEqual(recorded.amountMinor, 0)
        XCTAssertEqual(recorded.currency, "TWD")
        XCTAssertEqual(recorded.originalAmountMinor, -1_500_00)
        XCTAssertEqual(recorded.originalCurrency, "JPY")
        XCTAssertTrue(recorded.pending)
        XCTAssertTrue(recorded.isAwaitingSettlement)
    }

    func testForeignCardPurchaseMatchesItsLaterBankSettlement() throws {
        let account = CachedAccount(name: "Debit card", institution: "Bank", kind: "checking", amountMinor: 10_000_00, currency: "TWD")
        context.insert(account)

        AccountActionService.record(
            amountMinor: 1_500_00,
            description: "Japan purchase",
            category: "Shopping",
            date: Date(),
            direction: .moneyOut,
            account: account,
            context: context,
            purchaseCurrency: "JPY"
        )
        let manual = try XCTUnwrap(context.fetch(FetchDescriptor<CachedTransaction>()).first)
        let imported = transaction(
            title: "JAPAN STORE",
            amountMinor: -315_00,
            currency: "TWD",
            accountID: account.id,
            category: "Shopping",
            source: "automation",
            originalAmount: Money(amountMinor: -1_500_00, currency: "JPY")
        )

        let candidate = TransactionMerger.pair(manual, imported)

        XCTAssertNotNil(candidate)
        XCTAssertEqual(candidate?.manual.id, manual.id)
        XCTAssertEqual(candidate?.imported.id, imported.id)
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

    func testRecurringMatcherLinksForeignPurchaseAwaitingSettlementAndSkipsPausedBills() throws {
        let timestamp = "2026-10-29T00:00:00Z"
        let purchase = CachedTransaction(dto: TransactionDTO(id: "foreign", accountId: "account-1", description: "Netflix", amount: Money(amountMinor: 0, currency: "TWD"), originalAmount: Money(amountMinor: -1500, currency: "USD"), bookedAt: timestamp, pending: true, category: "Entertainment", updatedAt: timestamp))
        let bill = RecurringPayment(name: "Netflix", amountMinor: 1500, currency: "USD", frequency: "monthly", nextDate: Date(), accountId: "account-1", category: "Entertainment", isActive: false)
        context.insert(purchase)
        context.insert(bill)
        XCTAssertFalse(autoLinkRecurringPayment(purchase, payments: [bill], context: context))
        bill.isActive = true
        XCTAssertTrue(autoLinkRecurringPayment(purchase, payments: [bill], context: context))
        XCTAssertEqual(purchase.recurringPaymentId, bill.id)
        XCTAssertEqual(purchase.amountMinor, 0)
    }

    func testRecurringSyncAcceptsISOAndReferenceDateAndPreservesPausedState() throws {
        for date in [#""2026-10-05T00:00:00.000Z""#, "812851200"] {
            try engine.apply([change(1, entity: "recurringPayment", id: "bill-date", value: "{\"id\":\"bill-date\",\"name\":\"Rent\",\"amountMinor\":100,\"currency\":\"TWD\",\"frequency\":\"monthly\",\"nextDate\":\(date),\"category\":\"Bills\",\"isActive\":false}")], context: context)
            let bill = try XCTUnwrap(context.fetch(FetchDescriptor<RecurringPayment>()).first)
            XCTAssertFalse(bill.isActive)
            if date.hasPrefix("\"") {
                XCTAssertEqual(bill.nextDate, LedgerlyISODate.parse("2026-10-05T00:00:00Z"))
            } else {
                XCTAssertEqual(bill.nextDate.timeIntervalSinceReferenceDate, 812851200)
            }
        }
    }

    func testDeletingRecurringUpsertsPreservesDeleteAndOtherBills() throws {
        context.insert(PendingRecurringMutation(entityId: "removed", action: "upsert"))
        context.insert(PendingRecurringMutation(entityId: "removed", action: "delete"))
        context.insert(PendingRecurringMutation(entityId: "other", action: "upsert"))
        try context.save()
        try removePendingRecurringUpserts(paymentID: "removed", context: context)
        try context.save()
        let pending = try context.fetch(FetchDescriptor<PendingRecurringMutation>())
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.contains { $0.entityId == "removed" && $0.action == "delete" })
        XCTAssertTrue(pending.contains { $0.entityId == "other" && $0.action == "upsert" })
    }

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

    func testRecurringBillCanBeLinkedManuallyAcrossSettlementCurrencies() {
        let yenBill = RecurringPayment(name: "Japan service", amountMinor: 1_000_00, currency: "JPY", frequency: "monthly", nextDate: Date(), accountId: "account-1", category: "Bills")
        let otherAccount = RecurringPayment(name: "Other account", amountMinor: 1_000_00, currency: "JPY", frequency: "monthly", nextDate: Date(), accountId: "account-2", category: "Bills")

        XCTAssertEqual(RecurringPaymentMatcher.linkablePayments(accountID: "account-1", payments: [yenBill, otherAccount]).map(\.id), [yenBill.id])
        XCTAssertTrue(RecurringPaymentMatcher.compatiblePayments(currency: "TWD", accountID: "account-1", payments: [yenBill]).isEmpty)
    }

    func testRecurringMatcherUsesOriginalPurchaseCurrency() {
        let transaction = transaction(title: "Japan service", amountMinor: -215_00, currency: "TWD", accountID: "account-1", category: "Bills", originalAmount: Money(amountMinor: -1_000_00, currency: "JPY"))
        let yenBill = RecurringPayment(name: "Japan service", amountMinor: 1_000_00, currency: "JPY", frequency: "monthly", nextDate: Date(), accountId: "account-1", category: "Bills")

        let match = RecurringPaymentMatcher.bestMatch(for: transaction, payments: [yenBill])
        XCTAssertEqual(match?.payment.id, yenBill.id)
        XCTAssertTrue(match?.shouldAutoLink ?? false)
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
        context.insert(CachedTransaction(dto: TransactionDTO(id: "transaction-1", accountId: account.id, description: "Coffee", amount: Money(amountMinor: -150, currency: "TWD"), originalAmount: Money(amountMinor: -700, currency: "JPY"), bookedAt: timestamp, pending: false, category: "Dining", recurringPaymentId: "recurring-1", updatedAt: timestamp)))
        let original = try XCTUnwrap(context.fetch(FetchDescriptor<CachedTransaction>()).first)
        original.balanceImpactMinor = 0
        original.recurringPaymentUnlinked = true
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
        XCTAssertEqual(try destination.fetch(FetchDescriptor<CachedTransaction>()).first?.originalCurrency, "JPY")
        XCTAssertEqual(try destination.fetch(FetchDescriptor<CachedTransaction>()).first?.balanceImpactMinor, 0)
        XCTAssertEqual(try destination.fetch(FetchDescriptor<CachedTransaction>()).first?.recurringPaymentUnlinked, true)
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

    func testTransactionSearchMatchesMeaningfulFields() {
        let account = CachedAccount(name: "School Cash", institution: "Test Bank", kind: "cash", amountMinor: 0, currency: "TWD")
        let item = transaction(title: "Campus lunch", amountMinor: -120_00, currency: "TWD", accountID: account.id, category: "Food")
        XCTAssertTrue(TransactionSearch.matches("campus", transaction: item, account: account, recurringPayment: nil))
        XCTAssertTrue(TransactionSearch.matches("food", transaction: item, account: account, recurringPayment: nil))
        XCTAssertTrue(TransactionSearch.matches("school cash", transaction: item, account: account, recurringPayment: nil))
        XCTAssertFalse(TransactionSearch.matches("train ticket", transaction: item, account: account, recurringPayment: nil))
    }

    func testActivityDateFiltersUseTheSelectedWindow() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let tenDaysAgo = calendar.date(byAdding: .day, value: -10, to: now)!
        XCTAssertFalse(ActivityDateFilter.includes(tenDaysAgo, filter: .last7Days, customStart: now, customEnd: now, now: now, calendar: calendar))
        XCTAssertTrue(ActivityDateFilter.includes(tenDaysAgo, filter: .last30Days, customStart: now, customEnd: now, now: now, calendar: calendar))

        let customStart = calendar.date(byAdding: .day, value: -12, to: now)!
        let customEnd = calendar.date(byAdding: .day, value: -8, to: now)!
        XCTAssertTrue(ActivityDateFilter.includes(tenDaysAgo, filter: .custom, customStart: customStart, customEnd: customEnd, now: now, calendar: calendar))
        XCTAssertTrue(ActivityDateFilter.includes(tenDaysAgo, filter: .custom, customStart: customEnd, customEnd: customStart, now: now, calendar: calendar))
    }

    func testLinkingExistingReimbursementDoesNotChangeBalance() throws {
        let account = CachedAccount(name: "Checking", institution: "Bank", kind: "checking", amountMinor: 50_000, currency: "TWD")
        let expense = transaction(title: "School supplies", amountMinor: -2_000, currency: "TWD", accountID: account.id, category: "School")
        expense.reimbursementStatus = "pending"
        let payment = transaction(title: "Dad paid me", amountMinor: 2_000, currency: "TWD", accountID: account.id, category: "Transfer")
        context.insert(account); context.insert(expense); context.insert(payment)
        ReimbursementService.link(expense, to: payment, context: context)
        XCTAssertEqual(account.amountMinor, 50_000)
        XCTAssertEqual(expense.reimbursementStatus, "reimbursed")
        XCTAssertEqual(expense.reimbursementTransactionId, payment.id)
        XCTAssertEqual(payment.reimbursementTransactionId, expense.id)
    }

    func testOneReimbursementCanCoverMultipleExpenses() throws {
        let account = CachedAccount(name: "Checking", institution: "Bank", kind: "checking", amountMinor: 50_000, currency: "TWD")
        let lunch = transaction(title: "School lunch", amountMinor: -1_200, currency: "TWD", accountID: account.id, category: "School")
        let supplies = transaction(title: "School supplies", amountMinor: -2_000, currency: "TWD", accountID: account.id, category: "School")
        lunch.reimbursementStatus = "pending"
        supplies.reimbursementStatus = "pending"
        let payment = transaction(title: "Dad paid me", amountMinor: 4_000, currency: "TWD", accountID: account.id, category: "Transfer")
        context.insert(account); context.insert(lunch); context.insert(supplies); context.insert(payment)

        ReimbursementService.link([lunch, supplies], to: payment, context: context)

        XCTAssertEqual(account.amountMinor, 50_000)
        XCTAssertEqual(lunch.reimbursementStatus, "reimbursed")
        XCTAssertEqual(supplies.reimbursementStatus, "reimbursed")
        XCTAssertEqual(lunch.reimbursementTransactionId, payment.id)
        XCTAssertEqual(supplies.reimbursementTransactionId, payment.id)
    }

    func testOneReimbursementCanBeLinkedFromTwoExpenseScreens() throws {
        let account = CachedAccount(name: "Checking", institution: "Bank", kind: "checking", amountMinor: 50_000, currency: "TWD")
        let lunch = transaction(title: "School lunch", amountMinor: -1_200, currency: "TWD", accountID: account.id, category: "School")
        let supplies = transaction(title: "School supplies", amountMinor: -2_000, currency: "TWD", accountID: account.id, category: "School")
        let payment = transaction(title: "Dad paid me", amountMinor: 4_000, currency: "TWD", accountID: account.id, category: "Transfer")
        context.insert(account); context.insert(lunch); context.insert(supplies); context.insert(payment)

        ReimbursementService.link(lunch, to: payment, context: context)
        ReimbursementService.link(supplies, to: payment, context: context)

        XCTAssertEqual(lunch.reimbursementTransactionId, payment.id)
        XCTAssertEqual(supplies.reimbursementTransactionId, payment.id)
        XCTAssertEqual(lunch.reimbursementStatus, "reimbursed")
        XCTAssertEqual(supplies.reimbursementStatus, "reimbursed")
    }

    func testLinkingExistingRefundDoesNotChangeBalance() {
        let account = CachedAccount(name: "Card", institution: "Bank", kind: "credit", amountMinor: 10_000, currency: "TWD")
        let expense = transaction(title: "Returned item", amountMinor: -3_000, currency: "TWD", accountID: account.id, category: "Shopping")
        let refund = transaction(title: "Merchant refund", amountMinor: 3_000, currency: "TWD", accountID: account.id, category: "Refund")
        context.insert(account); context.insert(expense); context.insert(refund)
        RefundService.link(expense: expense, refund: refund, context: context)
        XCTAssertEqual(account.amountMinor, 10_000)
        XCTAssertEqual(expense.refundTransactionId, refund.id)
        XCTAssertEqual(refund.refundedTransactionId, expense.id)
    }

    func testCreatingRefundChangesBalanceExactlyOnce() {
        let account = CachedAccount(name: "Card", institution: "Bank", kind: "credit", amountMinor: 10_000, currency: "TWD")
        let expense = transaction(title: "Returned item", amountMinor: -3_000, currency: "TWD", accountID: account.id, category: "Shopping")
        context.insert(account); context.insert(expense)
        let refund = RefundService.create(for: expense, into: account, context: context)
        XCTAssertEqual(refund.amountMinor, 3_000)
        XCTAssertEqual(refund.source, "refund")
        XCTAssertEqual(account.amountMinor, 13_000)
        XCTAssertEqual(expense.refundTransactionId, refund.id)
        XCTAssertEqual(refund.refundedTransactionId, expense.id)
    }

    func testTransactionDTOCarriesRefundLinks() throws {
        let payload = #"{"id":"refund","accountId":"a1","description":"Refund","amount":{"amountMinor":450,"currency":"USD"},"bookedAt":"2026-09-21T10:00:00.000Z","pending":false,"refundedTransactionId":"purchase","updatedAt":"2026-09-21T10:00:00.000Z"}"#
        let transaction = try JSONDecoder().decode(TransactionDTO.self, from: Data(payload.utf8))
        XCTAssertEqual(transaction.refundedTransactionId, "purchase")
        XCTAssertNil(transaction.refundTransactionId)
    }

    private func transaction(title: String, amountMinor: Int, currency: String, accountID: String, category: String?, source: String? = nil, originalAmount: Money? = nil) -> CachedTransaction {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(), accountId: accountID, description: title,
            amount: Money(amountMinor: amountMinor, currency: currency), originalAmount: originalAmount, bookedAt: timestamp,
            pending: false, category: category, source: source, updatedAt: timestamp
        ))
    }
}

private final class PagedSyncURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "ledgerly.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data: Data
            if request.url?.path == "/v1/config" {
                data = Data(#"{"registrationEnabled":false,"convexUrl":"https://convex.test","serverVersion":"1","syncProtocolVersion":2}"#.utf8)
            } else {
                var body = request.httpBody
                if body == nil, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var collected = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        collected.append(buffer, count: count)
                    }
                    body = collected
                }
                let payload = try JSONSerialization.jsonObject(with: body ?? Data("{}".utf8)) as? [String: Any]
                let start = payload?["cursor"] as? String == "500" ? 500 : 0
                let end = start == 0 ? 500 : 501
                let changes = (start..<end).map { index in
                    SyncChange(sequence: index + 1, entity: "account", entityId: "page-\(index)", action: "upsert", value: .object([
                        "id": .string("page-\(index)"), "name": .string("Cash"), "institution": .string("Manual"), "kind": .string("cash"),
                        "balance": .object(["amountMinor": .number(0), "currency": .string("TWD")]), "updatedAt": .string("2026-01-01T00:00:00Z")
                    ]))
                }
                data = try JSONEncoder().encode(SyncResponse(cursor: String(end), changes: changes, acceptedMutationIds: []))
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
