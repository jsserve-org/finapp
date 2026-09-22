import type { InferSelectModel } from "drizzle-orm";
import type { accounts, transactions } from "../db/schema";

export function serializeAccount(row: InferSelectModel<typeof accounts>) {
  return {
    id: row.id, name: row.name, institution: row.institution, kind: row.kind,
    balance: { amountMinor: row.balanceMinor, currency: row.currency }, updatedAt: row.updatedAt.toISOString(),
  };
}

export function serializeTransaction(row: InferSelectModel<typeof transactions>) {
  return {
    id: row.id, accountId: row.accountId, description: row.description,
    amount: { amountMinor: row.amountMinor, currency: row.currency }, bookedAt: row.bookedAt.toISOString(),
    pending: row.pending, ...(row.category ? { category: row.category } : {}), updatedAt: row.updatedAt.toISOString(),
  };
}
