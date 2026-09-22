import { and, eq } from "drizzle-orm";
import { db } from "../db";
import { accounts, automationRuns, bankConnections, syncChanges, transactions } from "../db/schema";
import { serializeAccount, serializeTransaction } from "../domain/serializers";
import type { BankProvider } from "./provider";

export async function runConnection(connectionId: string, userId: string, provider: BankProvider) {
  const [connection] = await db.select().from(bankConnections).where(and(eq(bankConnections.id, connectionId), eq(bankConnections.userId, userId))).limit(1);
  if (!connection) throw new Error("CONNECTION_NOT_FOUND");
  const [run] = await db.insert(automationRuns).values({ connectionId }).returning();

  try {
    const health = await provider.checkConnection(connection.providerItemId);
    if (!health.ok) throw new Error(health.reason ?? "PROVIDER_UNAVAILABLE");
    const snapshot = await provider.fetchSnapshot(connection.providerItemId);

    await db.transaction(async (tx) => {
      const accountIds = new Map<string, string>();
      for (const incoming of snapshot.accounts) {
        const [account] = await tx.insert(accounts).values({
          userId, connectionId, providerAccountId: incoming.providerId, name: incoming.name,
          institution: incoming.institution, kind: incoming.kind, balanceMinor: incoming.balanceMinor, currency: incoming.currency,
        }).onConflictDoUpdate({
          target: [accounts.connectionId, accounts.providerAccountId],
          set: { name: incoming.name, balanceMinor: incoming.balanceMinor, currency: incoming.currency, updatedAt: new Date() },
        }).returning();
        accountIds.set(incoming.providerId, account.id);
        await tx.insert(syncChanges).values({ userId, entity: "account", entityId: account.id, action: "upsert", value: serializeAccount(account) });
      }

      for (const incoming of snapshot.transactions) {
        const accountId = accountIds.get(incoming.providerAccountId);
        if (!accountId) continue;
        const [transaction] = await tx.insert(transactions).values({
          userId, accountId, providerTransactionId: incoming.providerId, description: incoming.description,
          amountMinor: incoming.amountMinor, currency: incoming.currency, bookedAt: incoming.bookedAt, pending: incoming.pending,
        }).onConflictDoUpdate({
          target: [transactions.accountId, transactions.providerTransactionId],
          set: { description: incoming.description, amountMinor: incoming.amountMinor, pending: incoming.pending, updatedAt: new Date() },
        }).returning();
        await tx.insert(syncChanges).values({ userId, entity: "transaction", entityId: transaction.id, action: "upsert", value: serializeTransaction(transaction) });
      }

      const now = new Date();
      await tx.update(bankConnections).set({ status: "healthy", lastSuccessAt: now, lastError: null, nextCheckAt: new Date(now.getTime() + 15 * 60_000), updatedAt: now }).where(eq(bankConnections.id, connectionId));
      await tx.update(automationRuns).set({ state: "succeeded", finishedAt: now, diagnostics: { accounts: snapshot.accounts.length, transactions: snapshot.transactions.length } }).where(eq(automationRuns.id, run.id));
    });
    return { runId: run.id, state: "succeeded" as const };
  } catch (error) {
    const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
    const now = new Date();
    await db.update(bankConnections).set({ status: "degraded", lastError: message, nextCheckAt: new Date(now.getTime() + 5 * 60_000), updatedAt: now }).where(eq(bankConnections.id, connectionId));
    await db.update(automationRuns).set({ state: "failed", finishedAt: now, errorCode: message }).where(eq(automationRuns.id, run.id));
    throw error;
  }
}
