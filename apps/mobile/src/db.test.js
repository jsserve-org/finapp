import { expect, it, mock } from "bun:test";
import { Database } from "bun:sqlite";

const sqlite = new Database(":memory:");
mock.module("expo-sqlite", () => ({ openDatabaseSync: () => ({
  execSync: (sql) => sqlite.exec(sql),
  runSync: (sql, ...params) => sqlite.query(sql).run(...params),
  getAllSync: (sql, ...params) => sqlite.query(sql).all(...params),
  withTransactionSync: (callback) => sqlite.transaction(callback)(),
}) }));
const db = await import("./db");

it("queues recurring payments atomically and reads server dates", () => {
  db.initializeDatabase();
  const payment = db.createRecurringPayment({ name: "Rent", amountMinor: 100, currency: "USD", frequency: "monthly", nextDate: "2026-11-01T00:00:00.000Z", category: "Bills" });
  expect(db.cachedRecurringPayments()).toEqual([payment]);
  const operation = db.pendingOperations()[0];
  expect(operation.entity).toBe("recurringPayment");
  expect(operation.value.nextDate).toBe((Date.parse(payment.nextDate) - Date.UTC(2001, 0, 1)) / 1000);
  db.applySync({ cursor: "1", acceptedMutationIds: [], changes: [{ sequence: 1, entity: "recurringPayment", entityId: payment.id, action: "upsert", value: operation.value }] });
  expect(db.cachedRecurringPayments()[0]?.nextDate).toBe(payment.nextDate);
});

it("migrates legacy recurring payments once and preserves them", () => {
  const payment = { id: "legacy", name: "Legacy", nextDate: "2026-11-01T00:00:00.000Z" };
  sqlite.query("INSERT INTO cache VALUES ('recurring', ?, ?)").run(payment.id, JSON.stringify(payment));
  db.initializeDatabase();
  db.initializeDatabase();
  expect(db.cachedRecurringPayments().some((item) => item.id === "legacy")).toBe(true);
  expect(db.pendingOperations().filter((operation) => operation.entityId === "legacy")).toHaveLength(1);
});

it("migrates numeric reference dates and retains invalid legacy rows without syncing null", () => {
  for (const payment of [{ id: "numeric", nextDate: 812851200 }, { id: "invalid-date", nextDate: "garbage" }]) {
    sqlite.query("INSERT INTO cache VALUES ('recurring', ?, ?)").run(payment.id, JSON.stringify(payment));
  }
  db.initializeDatabase();
  const numeric = db.pendingOperations().find((operation) => operation.entityId === "numeric");
  expect(numeric.value.nextDate).toBe(812851200);
  expect(db.cachedRecurringPayments().find((payment) => payment.id === "numeric").nextDate).toBe(new Date(Date.UTC(2001, 0, 1) + 812851200000).toISOString());
  expect(db.pendingOperations().some((operation) => operation.entityId === "invalid-date")).toBe(false);
  expect(sqlite.query("SELECT id FROM cache WHERE kind = 'recurring'").all()).toEqual([{ id: "invalid-date" }]);
});

it("records a transaction and its account balance in one local transaction", () => {
  const account = db.createLocalAccount({ name: "Cash", institution: "Manual", kind: "cash", amountMinor: 10000, currency: "TWD" });
  const transaction = db.createLocalTransaction({ accountId: account.id, description: "Lunch", amountMinor: -1250 });
  expect(transaction.amount).toEqual({ amountMinor: -1250, currency: "TWD" });
  expect(transaction.balanceImpactMinor).toBe(-1250);
  expect(db.cachedAccounts().find(item => item.id === account.id).balance.amountMinor).toBe(8750);
  expect(db.cachedTransactions().some(item => item.id === transaction.id)).toBe(true);
  const queued = db.pendingOperations().filter(item => item.mutationId.includes(transaction.id));
  expect(queued.map(item => item.entity)).toEqual(["account", "transaction"]);
});

it("rolls back the balance and transaction if queueing fails", () => {
  const account = db.createLocalAccount({ name: "Atomic", institution: "Manual", kind: "cash", amountMinor: 10000, currency: "TWD" });
  const before = db.pendingOperations().length;
  sqlite.exec("CREATE TRIGGER fail_transaction_outbox BEFORE INSERT ON outbox WHEN NEW.mutation_id LIKE 'transaction-%' BEGIN SELECT RAISE(ABORT, 'test failure'); END");
  try { expect(() => db.createLocalTransaction({ accountId: account.id, description: "Fail", amountMinor: -100 })).toThrow(); }
  finally { sqlite.exec("DROP TRIGGER fail_transaction_outbox"); }
  expect(db.cachedAccounts().find(item => item.id === account.id).balance.amountMinor).toBe(10000);
  expect(db.cachedTransactions().some(item => item.accountId === account.id)).toBe(false);
  expect(db.pendingOperations()).toHaveLength(before);
});
