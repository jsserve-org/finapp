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
