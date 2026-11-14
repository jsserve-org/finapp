import * as SQLite from "expo-sqlite";
import { recurringDateToISO } from "./format";
import type {
  Account,
  RecurringPayment,
  StockHolding,
  StockTrade,
  SyncChange,
  SyncEntity,
  SyncOperation,
  SyncResponse,
  Transaction,
  TransactionFrequency,
} from "./types";

let database: SQLite.SQLiteDatabase | null = null;

type Listener = () => void;
const listeners = new Set<Listener>();

/** Screens subscribe to this so local edits and syncs redraw immediately. */
export function subscribe(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function notifyChanged() {
  listeners.forEach((listener) => listener());
}

function db(): SQLite.SQLiteDatabase {
  if (!database) database = SQLite.openDatabaseSync("ledgerly.db");
  return database;
}

export function initializeDatabase() {
  const sqlite = db();
  sqlite.execSync(`
    PRAGMA journal_mode = WAL;
    CREATE TABLE IF NOT EXISTS cache (
      kind TEXT NOT NULL,
      id TEXT NOT NULL,
      value TEXT NOT NULL,
      version INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (kind, id)
    );
    CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS outbox (
      mutation_id TEXT PRIMARY KEY,
      entity TEXT NOT NULL,
      action TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      value TEXT,
      base_version INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    );
    CREATE UNIQUE INDEX IF NOT EXISTS outbox_entity ON outbox (entity, entity_id);
    CREATE INDEX IF NOT EXISTS cache_kind ON cache (kind);
  `);
}

// MARK: - Cache

export function readCache<T>(kind: SyncEntity): T[] {
  return db()
    .getAllSync<{ value: string }>("SELECT value FROM cache WHERE kind = ?", kind)
    .map((row) => JSON.parse(row.value) as T);
}

export function getCached<T>(kind: SyncEntity, id: string): T | null {
  const row = db().getFirstSync<{ value: string }>("SELECT value FROM cache WHERE kind = ? AND id = ?", kind, id);
  return row ? (JSON.parse(row.value) as T) : null;
}

export function cachedVersion(kind: SyncEntity, id: string): number {
  return db().getFirstSync<{ version: number }>("SELECT version FROM cache WHERE kind = ? AND id = ?", kind, id)?.version ?? 0;
}

export function putCached(kind: SyncEntity, id: string, value: unknown, version = 0) {
  db().runSync(
    "INSERT INTO cache (kind, id, value, version) VALUES (?, ?, ?, ?) ON CONFLICT(kind, id) DO UPDATE SET value = excluded.value, version = excluded.version",
    kind,
    id,
    JSON.stringify(value),
    version,
  );
}

export function deleteCached(kind: SyncEntity, id: string) {
  db().runSync("DELETE FROM cache WHERE kind = ? AND id = ?", kind, id);
}

export const cachedAccounts = () => readCache<Account>("account").sort((a, b) => a.name.localeCompare(b.name));
export const cachedTransactions = () => readCache<Transaction>("transaction");
export const cachedRecurringPayments = () =>
  readCache<RecurringPayment>("recurringPayment").sort((a, b) => a.nextDate.localeCompare(b.nextDate));
export const cachedHoldings = () => readCache<StockHolding>("stockHolding").sort((a, b) => a.symbol.localeCompare(b.symbol));
export const cachedTrades = () => readCache<StockTrade>("stockTrade");

/** Newest first, capped like the native app so Activity stays responsive. */
export function cachedTransactionsNewest(limit = 500): Transaction[] {
  return cachedTransactions()
    .sort((a, b) => b.bookedAt.localeCompare(a.bookedAt))
    .slice(0, limit);
}

// MARK: - Settings

export function getSetting(key: string): string | null {
  return db().getFirstSync<{ value: string }>("SELECT value FROM settings WHERE key = ?", key)?.value ?? null;
}

export function setSetting(key: string, value: string) {
  db().runSync("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", key, value);
}

export const cursor = () => getSetting("cursor") ?? undefined;

// MARK: - Outbox

type QueuedOperation = {
  mutationId: string;
  entity: SyncEntity;
  action: "upsert" | "delete";
  entityId: string;
  value: Record<string, unknown> | null;
  baseVersion: number;
  createdAt: string;
};

/** Coalesces pending work per entity: a later edit replaces the earlier queue entry. */
export function enqueue(operation: Omit<QueuedOperation, "mutationId" | "createdAt"> & { mutationId?: string }) {
  db().runSync(
    `INSERT INTO outbox (mutation_id, entity, action, entity_id, value, base_version, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(entity, entity_id) DO UPDATE SET
       action = excluded.action,
       value = excluded.value,
       base_version = excluded.base_version`,
    operation.mutationId ?? crypto.randomUUID(),
    operation.entity,
    operation.action,
    operation.entityId,
    operation.value ? JSON.stringify(operation.value) : null,
    operation.baseVersion,
    new Date().toISOString(),
  );
}

export function dropQueued(entity: SyncEntity, entityId: string) {
  db().runSync("DELETE FROM outbox WHERE entity = ? AND entity_id = ?", entity, entityId);
}

export function pendingOperations(): SyncOperation[] {
  return db()
    .getAllSync<{ mutation_id: string; entity: SyncEntity; action: "upsert" | "delete"; entity_id: string; value: string | null; base_version: number }>(
      "SELECT * FROM outbox ORDER BY created_at",
    )
    .map((row) => ({
      mutationId: row.mutation_id,
      entity: row.entity,
      action: row.action,
      entityId: row.entity_id,
      value: row.value ? (JSON.parse(row.value) as Record<string, unknown>) : null,
      baseVersion: row.base_version,
    }));
}

export function pendingMutationCount(): number {
  return db().getFirstSync<{ count: number }>("SELECT COUNT(*) AS count FROM outbox")?.count ?? 0;
}

export function acceptMutations(ids: string[]) {
  const sqlite = db();
  sqlite.withTransactionSync(() => {
    for (const id of ids) sqlite.runSync("DELETE FROM outbox WHERE mutation_id = ?", id);
  });
}

// MARK: - Sync application

type UpsertFields = Record<string, unknown>;

function decodeAccount(value: UpsertFields, existing: Account | null): Account | null {
  const merged = existing ? { ...existing, ...value } : value;
  const balance = merged.balance as { amountMinor?: unknown; currency?: unknown } | undefined;
  if (typeof merged.name !== "string" || !balance || typeof balance.amountMinor !== "number" || typeof balance.currency !== "string") {
    return existing;
  }
  return {
    id: String(merged.id ?? existing?.id ?? ""),
    name: merged.name,
    institution: typeof merged.institution === "string" ? merged.institution : (existing?.institution ?? "Manual"),
    kind: typeof merged.kind === "string" ? merged.kind : (existing?.kind ?? "checking"),
    balance: { amountMinor: balance.amountMinor, currency: balance.currency },
    updatedAt: typeof merged.updatedAt === "string" ? merged.updatedAt : (existing?.updatedAt ?? new Date().toISOString()),
  };
}

function decodeTransaction(value: UpsertFields): Transaction | null {
  const amount = value.amount as { amountMinor?: unknown; currency?: unknown } | undefined;
  if (typeof value.accountId !== "string" || typeof value.description !== "string" || typeof value.bookedAt !== "string") return null;
  if (!amount || typeof amount.amountMinor !== "number" || typeof amount.currency !== "string") return null;
  const original = value.originalAmount as { amountMinor?: unknown; currency?: unknown } | undefined;
  const text = (item: unknown) => (typeof item === "string" ? item : undefined);
  return {
    id: String(value.id ?? ""),
    accountId: value.accountId,
    description: value.description,
    amount: { amountMinor: amount.amountMinor, currency: amount.currency },
    originalAmount:
      original && typeof original.amountMinor === "number" && typeof original.currency === "string"
        ? { amountMinor: original.amountMinor, currency: original.currency }
        : undefined,
    bookedAt: value.bookedAt,
    pending: value.pending === true,
    category: text(value.category),
    categoryUserEdited: value.categoryUserEdited === true,
    recurringPaymentId: text(value.recurringPaymentId),
    source: text(value.source),
    expensePurpose: text(value.expensePurpose),
    reimbursementStatus: text(value.reimbursementStatus),
    reimbursementTransactionId: text(value.reimbursementTransactionId),
    refundTransactionId: text(value.refundTransactionId),
    refundedTransactionId: text(value.refundedTransactionId),
    transferId: text(value.transferId),
    transferAccountId: text(value.transferAccountId),
    transferDirection: text(value.transferDirection),
    balanceImpactMinor: typeof value.balanceImpactMinor === "number" ? value.balanceImpactMinor : undefined,
    updatedAt: typeof value.updatedAt === "string" ? value.updatedAt : value.bookedAt,
  };
}

function decodeRecurringPayment(value: UpsertFields): RecurringPayment | null {
  const nextDate = recurringDateToISO(value.nextDate);
  if (typeof value.name !== "string" || typeof value.amountMinor !== "number" || typeof value.currency !== "string" || !nextDate) return null;
  return {
    id: String(value.id ?? ""),
    name: value.name,
    amountMinor: value.amountMinor,
    currency: value.currency,
    frequency: (value.frequency as TransactionFrequency) ?? "monthly",
    nextDate,
    accountId: typeof value.accountId === "string" ? value.accountId : undefined,
    category: typeof value.category === "string" ? value.category : "Bills",
    isActive: value.isActive !== false,
    scheduleAnchorDay: typeof value.scheduleAnchorDay === "number" ? value.scheduleAnchorDay : undefined,
  };
}

function decodeHolding(value: UpsertFields): StockHolding | null {
  if (typeof value.symbol !== "string" || typeof value.quantity !== "number" || typeof value.currency !== "string") return null;
  return {
    id: String(value.id ?? ""),
    symbol: value.symbol,
    name: typeof value.name === "string" ? value.name : value.symbol,
    quantity: value.quantity,
    averageCostMinor: typeof value.averageCostMinor === "number" ? value.averageCostMinor : 0,
    currentPriceMinor: typeof value.currentPriceMinor === "number" ? value.currentPriceMinor : 0,
    currency: value.currency,
    linkedAccountId: typeof value.linkedAccountId === "string" ? value.linkedAccountId : undefined,
    updatedAt: typeof value.updatedAt === "string" ? value.updatedAt : new Date().toISOString(),
  };
}

function decodeTrade(value: UpsertFields): StockTrade | null {
  if (typeof value.holdingId !== "string" || typeof value.symbol !== "string" || typeof value.quantity !== "number") return null;
  return {
    id: String(value.id ?? ""),
    holdingId: value.holdingId,
    symbol: value.symbol,
    side: value.side === "sell" ? "sell" : "buy",
    quantity: value.quantity,
    priceMinor: typeof value.priceMinor === "number" ? value.priceMinor : 0,
    feesMinor: typeof value.feesMinor === "number" ? value.feesMinor : 0,
    currency: typeof value.currency === "string" ? value.currency : "TWD",
    tradedAt: typeof value.tradedAt === "string" ? value.tradedAt : new Date().toISOString(),
    linkedAccountId: typeof value.linkedAccountId === "string" ? value.linkedAccountId : undefined,
  };
}

export function applyChanges(changes: SyncChange[]) {
  const sqlite = db();
  sqlite.withTransactionSync(() => {
    for (const change of changes) {
      if (change.action === "delete") {
        deleteCached(change.entity, change.entityId);
        continue;
      }
      if (!change.value) continue;
      const value = change.value;
      switch (change.entity) {
        case "account": {
          const account = decodeAccount(value, getCached<Account>("account", change.entityId));
          if (account) putCached("account", change.entityId, account, change.sequence);
          break;
        }
        case "transaction": {
          const transaction = decodeTransaction({ id: change.entityId, ...value });
          if (transaction) {
            transaction.id = change.entityId;
            putCached("transaction", change.entityId, transaction, change.sequence);
          }
          break;
        }
        case "recurringPayment": {
          const payment = decodeRecurringPayment({ id: change.entityId, ...value });
          if (payment) putCached("recurringPayment", change.entityId, payment, change.sequence);
          break;
        }
        case "stockHolding": {
          const holding = decodeHolding({ id: change.entityId, ...value });
          if (holding) putCached("stockHolding", change.entityId, holding, change.sequence);
          break;
        }
        case "stockTrade": {
          const trade = decodeTrade({ id: change.entityId, ...value });
          if (trade) putCached("stockTrade", change.entityId, trade, change.sequence);
          break;
        }
      }
    }
  });
}

export function applySync(response: SyncResponse) {
  applyChanges(response.changes);
  acceptMutations(response.acceptedMutationIds);
  setSetting("cursor", response.cursor);
  setSetting("lastSyncAt", new Date().toISOString());
  notifyChanged();
}
