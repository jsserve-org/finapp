import SwiftData
import XCTest
@testable import Ledgerly

@MainActor
final class SyncEngineTests: XCTestCase {
    private var context: ModelContext!
    private var engine: SyncEngine!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CachedAccount.self, CachedTransaction.self, SyncSetting.self, PendingMutation.self, configurations: config)
        context = ModelContext(container)
        context.autosaveEnabled = false
        engine = SyncEngine(api: APIClient.shared)
    }

    // MARK: - JSONValue

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
}
