import { expect, it, mock } from "bun:test";
import { Database } from "bun:sqlite";

const sqlite = new Database(":memory:");
mock.module("expo-sqlite", () => ({
  openDatabaseSync: () => ({
    execSync: (sql: string) => sqlite.exec(sql),
    runSync: (sql: string, ...params: unknown[]) => sqlite.query(sql).run(...(params as never[])),
    getAllSync: (sql: string, ...params: unknown[]) => sqlite.query(sql).all(...(params as never[])),
    getFirstSync: (sql: string, ...params: unknown[]) => sqlite.query(sql).get(...(params as never[])) ?? null,
    withTransactionSync: (callback: () => void) => sqlite.transaction(callback)(),
  }),
}));

const db = await import("./db");

function reset() {
  sqlite.exec("DROP TABLE IF EXISTS cache; DROP TABLE IF EXISTS settings; DROP TABLE IF EXISTS outbox;");
  db.initializeDatabase();
}

const accountValue = {
  id: "acct-1",
  name: "Checking",
  institution: "Bank",
  kind: "checking",
  balance: { amountMinor: 5000, currency: "TWD" },
  updatedAt: "2026-11-01T00:00:00.000Z",
};

it("coalesces queued edits per entity", () => {
  reset();
  db.enqueue({ entity: "account", action: "upsert", entityId: "acct-1", value: accountValue, baseVersion: 0 });
  db.enqueue({
    entity: "account",
    action: "upsert",
    entityId: "acct-1",
    value: { ...accountValue, name: "Renamed" },
    baseVersion: 0,
  });
  const operations = db.pendingOperations();
  expect(operations).toHaveLength(1);
  expect((operations[0].value as typeof accountValue).name).toBe("Renamed");
});

it("applies sync changes, cursor, and accepted mutations", () => {
  reset();
  db.enqueue({ entity: "transaction", action: "upsert", entityId: "tx-1", value: { id: "tx-1" }, baseVersion: 0 });
  const mutationId = db.pendingOperations()[0].mutationId;

  db.applySync({
    cursor: "42",
    acceptedMutationIds: [mutationId],
    changes: [
      { sequence: 41, entity: "account", entityId: "acct-1", action: "upsert", value: accountValue },
      {
        sequence: 42,
        entity: "transaction",
        entityId: "tx-1",
        action: "upsert",
        value: {
          accountId: "acct-1",
          description: "Lunch",
          amount: { amountMinor: -120, currency: "TWD" },
          bookedAt: "2026-11-02T04:00:00.000Z",
          pending: false,
          category: "Dining",
          updatedAt: "2026-11-02T04:00:00.000Z",
        },
      },
    ],
  });

  expect(db.cursor()).toBe("42");
  expect(db.pendingOperations()).toHaveLength(0);
  expect(db.cachedAccounts()[0].balance.amountMinor).toBe(5000);
  expect(db.cachedTransactions()[0].description).toBe("Lunch");
});

it("patches partial account updates instead of dropping names", () => {
  reset();
  db.applySync({
    cursor: "1",
    acceptedMutationIds: [],
    changes: [{ sequence: 1, entity: "account", entityId: "acct-2", action: "upsert", value: { ...accountValue, id: "acct-2" } }],
  });
  db.applySync({
    cursor: "2",
    acceptedMutationIds: [],
    changes: [
      {
        sequence: 2,
        entity: "account",
        entityId: "acct-2",
        action: "upsert",
        value: { id: "acct-2", balance: { amountMinor: 9000, currency: "TWD" } },
      },
    ],
  });
  expect(db.cachedAccounts().find((account) => account.id === "acct-2")?.name).toBe("Checking");
  expect(db.cachedAccounts().find((account) => account.id === "acct-2")?.balance.amountMinor).toBe(9000);
});

it("converts reference dates on recurring bills and honors deletions", () => {
  reset();
  db.applySync({
    cursor: "3",
    acceptedMutationIds: [],
    changes: [
      {
        sequence: 3,
        entity: "recurringPayment",
        entityId: "bill-1",
        action: "upsert",
        value: {
          name: "Rent",
          amountMinor: 2000000,
          currency: "TWD",
          frequency: "monthly",
          nextDate: 812851200,
          category: "Bills",
          isActive: true,
        },
      },
    ],
  });
  expect(db.cachedRecurringPayments()[0].nextDate).toBe(new Date(Date.UTC(2001, 0, 1) + 812851200000).toISOString());

  db.applySync({
    cursor: "4",
    acceptedMutationIds: [],
    changes: [{ sequence: 4, entity: "recurringPayment", entityId: "bill-1", action: "delete", value: null }],
  });
  expect(db.cachedRecurringPayments()).toHaveLength(0);
});
