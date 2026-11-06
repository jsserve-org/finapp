import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { addChange, requireSession } from "./lib";
import { mergeTransactionValue } from "./transactionMerge";
import { generateForUser, linkPayment, recurringDate } from "./recurring";
import { validateSyncValue } from "./syncValue";
import { repairAccounts, repairChanges } from "./repair";

const operationValidator = v.object({
  mutationId: v.string(),
  entity: v.union(v.literal("account"), v.literal("transaction"), v.literal("recurringPayment"), v.literal("stockHolding"), v.literal("stockTrade")),
  action: v.union(v.literal("upsert"), v.literal("delete")),
  entityId: v.string(),
  value: v.optional(v.any()),
  baseVersion: v.number(),
});

export const exchange = mutation({ args: { tokenHash: v.string(), cursor: v.string(), operations: v.array(operationValidator), now: v.number() }, handler: async (ctx, args) => {
  const session = await requireSession(ctx, args.tokenHash, args.now);
  await repairAccounts(ctx, session.userId);
  const acceptedMutationIds: string[] = [];
  for (const operation of args.operations.slice(0, 100)) {
    const prior = await ctx.db.query("mutations").withIndex("by_user_mutation", (q) => q.eq("userId", session.userId).eq("mutationId", operation.mutationId)).unique();
    if (prior) { acceptedMutationIds.push(operation.mutationId); continue; }
    if (operation.action === "upsert" && (!operation.value || typeof operation.value !== "object" || Array.isArray(operation.value))) throw new Error(`INVALID_SYNC_VALUE: ${operation.entity} ${operation.entityId}`);
    if (operation.entity === "account" && operation.action === "delete") {
      const account = await ctx.db.query("accounts").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", operation.entityId)).unique();
      if (account) await ctx.db.delete(account._id);
      const transactions = await ctx.db.query("transactions").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect();
      for (const transaction of transactions.filter((item) => !item.deleted && item.value?.accountId === operation.entityId)) {
        await ctx.db.patch(transaction._id, { deleted: true, version: transaction.version + 1 });
        await addChange(ctx, session.userId, "transaction", transaction.externalId, "delete", null);
      }
      const recurringPayments = await ctx.db.query("recurringPayments").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect();
      for (const payment of recurringPayments.filter((item) => !item.deleted && item.value?.accountId === operation.entityId)) {
        await ctx.db.patch(payment._id, { deleted: true, version: payment.version + 1 });
        await addChange(ctx, session.userId, "recurringPayment", payment.externalId, "delete", null);
      }
      const holdings = await ctx.db.query("stockHoldings").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect();
      for (const holding of holdings.filter((item) => !item.deleted && item.value?.linkedAccountId === operation.entityId)) {
        const value = { ...holding.value, linkedAccountId: null, updatedAt: new Date(args.now).toISOString() };
        await ctx.db.patch(holding._id, { value, version: holding.version + 1 });
        await addChange(ctx, session.userId, "stockHolding", holding.externalId, "upsert", value);
      }
      const trades = await ctx.db.query("stockTrades").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect();
      for (const trade of trades.filter((item) => !item.deleted && item.value?.linkedAccountId === operation.entityId)) {
        const value = { ...trade.value, linkedAccountId: null, updatedAt: new Date(args.now).toISOString() };
        await ctx.db.patch(trade._id, { value, version: trade.version + 1 });
        await addChange(ctx, session.userId, "stockTrade", trade.externalId, "upsert", value);
      }
      await addChange(ctx, session.userId, "account", operation.entityId, "delete", null);
      await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
      acceptedMutationIds.push(operation.mutationId);
      continue;
    }
    if (operation.entity === "account" && operation.action === "upsert") {
      const account = await ctx.db.query("accounts").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", operation.entityId)).unique();
      operation.value = { ...account?.value, ...operation.value };
      validateSyncValue(operation.entity, operation.entityId, operation.value);
      if (account) await ctx.db.patch(account._id, { value: operation.value, version: account.version + 1 });
      else await ctx.db.insert("accounts", { userId: session.userId, externalId: operation.entityId, value: operation.value, version: 1 });
      await addChange(ctx, session.userId, "account", operation.entityId, "upsert", operation.value);
      await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
      acceptedMutationIds.push(operation.mutationId);
      continue;
    }
    if (operation.entity === "recurringPayment") {
      const payment = await ctx.db.query("recurringPayments").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", operation.entityId)).unique();
      if (operation.action === "delete") {
        if (payment) await ctx.db.patch(payment._id, { deleted: true, version: payment.version + 1 });
        const linkedTransactions = await ctx.db.query("transactions").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect();
        for (const transaction of linkedTransactions.filter((item) => !item.deleted && item.value?.recurringPaymentId === operation.entityId)) {
          if (transaction.value?.source === "subscription" && transaction.value?.pending) {
            await ctx.db.patch(transaction._id, { deleted: true, version: transaction.version + 1 });
            await addChange(ctx, session.userId, "transaction", transaction.externalId, "delete", null);
            continue;
          }
          const value = { ...transaction.value, recurringPaymentId: null, updatedAt: new Date(args.now).toISOString() };
          await ctx.db.patch(transaction._id, { value, version: transaction.version + 1 });
          await addChange(ctx, session.userId, "transaction", transaction.externalId, "upsert", value);
        }
        await addChange(ctx, session.userId, "recurringPayment", operation.entityId, "delete", null);
      } else if (operation.value?.id === operation.entityId) {
        const oldDate = recurringDate(payment?.value?.nextDate);
        const newDate = recurringDate(operation.value.nextDate ?? payment?.value?.nextDate);
        const changedDate = oldDate?.getTime() !== newDate?.getTime();
        const incomingAnchor = operation.value.scheduleAnchorDay;
        operation.value = { ...payment?.value, ...operation.value };
        validateSyncValue(operation.entity, operation.entityId, operation.value);
        if ((!payment || changedDate) && incomingAnchor == null && newDate) {
          operation.value.scheduleAnchorDay = new Date(newDate.getTime() + 8 * 3600_000).getUTCDate();
        }
        if (payment?.value?.isActive === false && operation.value.isActive === true && !changedDate && newDate && newDate.getTime() < Date.now()) {
          const resumed = new Date();
          operation.value.nextDate = (resumed.getTime() - Date.UTC(2001, 0, 1)) / 1000;
          operation.value.scheduleAnchorDay = new Date(resumed.getTime() + 8 * 3600_000).getUTCDate();
        }
        const scheduleChanged = payment && (operation.value.frequency !== payment.value.frequency || operation.value.amountMinor !== payment.value.amountMinor || operation.value.currency !== payment.value.currency || operation.value.accountId !== payment.value.accountId || (changedDate && operation.value.scheduleAnchorDay !== payment.value.scheduleAnchorDay));
        if (scheduleChanged) {
          const transactions = await ctx.db.query("transactions").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect();
          for (const item of transactions.filter((row) => !row.deleted && row.value?.recurringPaymentId === operation.entityId && row.value?.source === "subscription" && row.value?.pending)) {
            await ctx.db.patch(item._id, { deleted: true, version: item.version + 1 });
            await addChange(ctx, session.userId, "transaction", item.externalId, "delete", null);
          }
        }
        if (payment) await ctx.db.patch(payment._id, { value: operation.value, deleted: false, version: payment.version + 1 });
        else await ctx.db.insert("recurringPayments", { userId: session.userId, externalId: operation.entityId, value: operation.value, version: 1, deleted: false });
        await addChange(ctx, session.userId, "recurringPayment", operation.entityId, "upsert", operation.value);
      } else {
        throw new Error(`INVALID_SYNC_VALUE: ${operation.entity} ${operation.entityId}`);
      }
      await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
      acceptedMutationIds.push(operation.mutationId);
      continue;
    }
    if (operation.entity === "stockHolding" || operation.entity === "stockTrade") {
      const table = operation.entity === "stockHolding" ? "stockHoldings" : "stockTrades";
      const record = await ctx.db.query(table).withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", operation.entityId)).unique();
      if (operation.action === "delete") {
        if (record) await ctx.db.patch(record._id, { deleted: true, version: record.version + 1 });
        await addChange(ctx, session.userId, operation.entity, operation.entityId, "delete", null);
      } else if (operation.value?.id === operation.entityId) {
        validateSyncValue(operation.entity, operation.entityId, operation.value);
        if (record) await ctx.db.patch(record._id, { value: operation.value, deleted: false, version: record.version + 1 });
        else await ctx.db.insert(table, { userId: session.userId, externalId: operation.entityId, value: operation.value, version: 1, deleted: false });
        await addChange(ctx, session.userId, operation.entity, operation.entityId, "upsert", operation.value);
      } else {
        throw new Error(`INVALID_SYNC_VALUE: ${operation.entity} ${operation.entityId}`);
      }
      await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
      acceptedMutationIds.push(operation.mutationId);
      continue;
    }
    if (operation.entity !== "transaction") continue;
    const transaction = await ctx.db.query("transactions").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", operation.entityId)).unique();
    if (operation.action === "upsert") {
      const accountId = operation.value?.accountId ?? transaction?.value?.accountId;
      const account = typeof accountId === "string" ? await ctx.db.query("accounts").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", accountId)).unique() : null;
      // A stale importer must not restore a deleted transaction or a deleted account's history.
      if (transaction?.deleted || !account) {
        await addChange(ctx, session.userId, "transaction", operation.entityId, "delete", null);
        await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
        acceptedMutationIds.push(operation.mutationId);
        continue;
      }
    }
    if (operation.action === "upsert" && operation.value?.id === operation.entityId) {
      if (session.actor === "automation" && transaction?.value?.recurringPaymentId === null) operation.value = { ...operation.value, recurringPaymentId: null };
      validateSyncValue(operation.entity, operation.entityId, { ...transaction?.value, ...operation.value });
      operation.value = await linkPayment(ctx, session.userId, { ...transaction?.value, ...operation.value });
    }
    if (!transaction && operation.entity === "transaction" && operation.action === "upsert" && operation.value?.id === operation.entityId && operation.value?.accountId && operation.value?.amount) {
      const value = {
        ...operation.value,
        categoryUserEdited: session.actor === "user" && Object.hasOwn(operation.value, "category"),
      };
      await ctx.db.insert("transactions", { userId: session.userId, externalId: operation.entityId, value, version: 1, deleted: false });
      await addChange(ctx, session.userId, "transaction", operation.entityId, "upsert", value);
      await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
      acceptedMutationIds.push(operation.mutationId);
      continue;
    }
    if (!transaction) {
      if (operation.action === "delete") {
        await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
        acceptedMutationIds.push(operation.mutationId);
      }
      continue;
    }
    const deleted = operation.action === "delete";
    if (!deleted) validateSyncValue(operation.entity, operation.entityId, { ...transaction.value, ...operation.value });
    const value = deleted ? null : mergeTransactionValue(
      transaction.value,
      operation.value,
      session.actor,
      new Date(args.now).toISOString(),
    );
    await ctx.db.patch(transaction._id, { value, deleted, version: transaction.version + 1 });
    await addChange(ctx, session.userId, "transaction", operation.entityId, operation.action, value);
    await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
    acceptedMutationIds.push(operation.mutationId);
  }
  await generateForUser(ctx, session.userId, Date.now());
  const after = Number(args.cursor) || 0;
  const changes = await ctx.db.query("changes").withIndex("by_user_sequence", (q) => q.eq("userId", session.userId).gt("sequence", after)).take(500);
  await repairChanges(ctx, session.userId, changes);
  return { cursor: String(changes.at(-1)?.sequence ?? after), changes: changes.map(({ sequence, entity, entityId, action, value }) => ({ sequence, entity, entityId, action, value })), acceptedMutationIds };
} });
