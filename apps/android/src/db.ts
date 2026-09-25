import type { Account, SyncResponse, Transaction } from "@ledgerly/contracts";
import * as SQLite from "expo-sqlite";

const database = SQLite.openDatabaseSync("ledgerly.db");

export function initializeDatabase() {
  database.execSync(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS cache (kind TEXT NOT NULL, id TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(kind, id));
    CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS outbox (mutation_id TEXT PRIMARY KEY, value TEXT NOT NULL);
  `);
}

export function readCache<T>(kind: "account" | "transaction" | "recurring"): T[] {
  return database.getAllSync<{ value: string }>("SELECT value FROM cache WHERE kind = ?", kind).map((row) => JSON.parse(row.value) as T);
}

export function applySync(result: SyncResponse) {
  database.withTransactionSync(() => {
    for (const change of result.changes) {
      if (change.action === "delete") database.runSync("DELETE FROM cache WHERE kind = ? AND id = ?", change.entity, change.entityId);
      else database.runSync("INSERT OR REPLACE INTO cache(kind, id, value) VALUES (?, ?, ?)", change.entity, change.entityId, JSON.stringify(change.value));
    }
    database.runSync("INSERT OR REPLACE INTO settings(key, value) VALUES ('cursor', ?)", result.cursor);
  });
}

export const cachedAccounts = () => readCache<Account>("account");
export const cachedTransactions = () => readCache<Transaction>("transaction");
export const cursor = () => database.getFirstSync<{ value: string }>("SELECT value FROM settings WHERE key = 'cursor'")?.value;
export type RecurringPayment = {
  id: string;
  name: string;
  amountMinor: number;
  currency: string;
  frequency: "weekly" | "everyTwoWeeks" | "monthly" | "yearly" | "everyTwoYears";
  nextDate: string;
  accountId?: string;
  category: string;
  isActive: boolean;
};
export const cachedRecurringPayments = () => readCache<RecurringPayment>("recurring");
export function createRecurringPayment(input: Omit<RecurringPayment, "id" | "isActive">) {
  const payment: RecurringPayment = { ...input, id: `recurring-${Date.now()}-${Math.random().toString(36).slice(2)}`, isActive: true };
  database.runSync("INSERT INTO cache(kind, id, value) VALUES ('recurring', ?, ?)", payment.id, JSON.stringify(payment));
  return payment;
}
export function createLocalAccount(input: { name: string; institution: string; kind: Account["kind"]; amountMinor: number; currency: string }) {
  const account: Account = { id: `local-${Date.now()}-${Math.random().toString(36).slice(2)}`, name: input.name, institution: input.institution || "Manual", kind: input.kind, balance: { amountMinor: input.amountMinor, currency: input.currency.toUpperCase() }, updatedAt: new Date().toISOString() };
  database.runSync("INSERT INTO cache(kind, id, value) VALUES ('account', ?, ?)", account.id, JSON.stringify(account));
  const operation = { mutationId: `mutation-${account.id}`, entity: "account", action: "upsert", entityId: account.id, value: account, baseVersion: 0 };
  database.runSync("INSERT OR REPLACE INTO outbox(mutation_id, value) VALUES (?, ?)", operation.mutationId, JSON.stringify(operation));
  return account;
}
export const pendingOperations = () => database.getAllSync<{ value: string }>("SELECT value FROM outbox").map((row) => JSON.parse(row.value));
export function acceptMutations(ids: string[]) { database.withTransactionSync(() => { for (const id of ids) database.runSync("DELETE FROM outbox WHERE mutation_id = ?", id); }); }
