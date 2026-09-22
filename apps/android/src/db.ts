import type { Account, SyncResponse, Transaction } from "@ledgerly/contracts";
import * as SQLite from "expo-sqlite";

const database = SQLite.openDatabaseSync("ledgerly.db");

export function initializeDatabase() {
  database.execSync(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS cache (kind TEXT NOT NULL, id TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(kind, id));
    CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
  `);
}

export function readCache<T>(kind: "account" | "transaction"): T[] {
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
