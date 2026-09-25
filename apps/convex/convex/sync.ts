import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { addChange, requireSession } from "./lib";

export const exchange = mutation({ args: { tokenHash: v.string(), cursor: v.string(), operations: v.array(v.any()), now: v.number() }, handler: async (ctx, args) => {
  const session = await requireSession(ctx, args.tokenHash, args.now);
  const acceptedMutationIds: string[] = [];
  for (const operation of args.operations.slice(0, 100)) {
    const prior = await ctx.db.query("mutations").withIndex("by_user_mutation", (q) => q.eq("userId", session.userId).eq("mutationId", operation.mutationId)).unique();
    if (prior) { acceptedMutationIds.push(operation.mutationId); continue; }
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
      await addChange(ctx, session.userId, "account", operation.entityId, "delete", null);
      await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
      acceptedMutationIds.push(operation.mutationId);
      continue;
    }
    if (operation.entity === "account" && operation.action === "upsert") {
      const account = await ctx.db.query("accounts").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", operation.entityId)).unique();
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
          const value = { ...transaction.value, recurringPaymentId: null, updatedAt: new Date(args.now).toISOString() };
          await ctx.db.patch(transaction._id, { value, version: transaction.version + 1 });
          await addChange(ctx, session.userId, "transaction", transaction.externalId, "upsert", value);
        }
        await addChange(ctx, session.userId, "recurringPayment", operation.entityId, "delete", null);
      } else if (operation.value?.id === operation.entityId) {
        if (payment) await ctx.db.patch(payment._id, { value: operation.value, deleted: false, version: payment.version + 1 });
        else await ctx.db.insert("recurringPayments", { userId: session.userId, externalId: operation.entityId, value: operation.value, version: 1, deleted: false });
        await addChange(ctx, session.userId, "recurringPayment", operation.entityId, "upsert", operation.value);
      } else {
        continue;
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
        if (record) await ctx.db.patch(record._id, { value: operation.value, deleted: false, version: record.version + 1 });
        else await ctx.db.insert(table, { userId: session.userId, externalId: operation.entityId, value: operation.value, version: 1, deleted: false });
        await addChange(ctx, session.userId, operation.entity, operation.entityId, "upsert", operation.value);
      } else {
        continue;
      }
      await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
      acceptedMutationIds.push(operation.mutationId);
      continue;
    }
    const transaction = await ctx.db.query("transactions").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", operation.entityId)).unique();
    if (!transaction && operation.entity === "transaction" && operation.action === "upsert" && operation.value?.id === operation.entityId && operation.value?.accountId && operation.value?.amount) {
      await ctx.db.insert("transactions", { userId: session.userId, externalId: operation.entityId, value: operation.value, version: 1, deleted: false });
      await addChange(ctx, session.userId, "transaction", operation.entityId, "upsert", operation.value);
      await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
      acceptedMutationIds.push(operation.mutationId);
      continue;
    }
    if (!transaction) continue;
    const deleted = operation.action === "delete";
    const value = deleted ? null : { ...transaction.value, ...operation.value, updatedAt: new Date(args.now).toISOString() };
    await ctx.db.patch(transaction._id, { value, deleted, version: transaction.version + 1 });
    await addChange(ctx, session.userId, "transaction", operation.entityId, operation.action, value);
    await ctx.db.insert("mutations", { userId: session.userId, mutationId: operation.mutationId });
    acceptedMutationIds.push(operation.mutationId);
  }
  const after = Number(args.cursor) || 0;
  const changes = await ctx.db.query("changes").withIndex("by_user_sequence", (q) => q.eq("userId", session.userId).gt("sequence", after)).take(500);
  return { cursor: String(changes.at(-1)?.sequence ?? after), changes: changes.map(({ sequence, entity, entityId, action, value }) => ({ sequence, entity, entityId, action, value })), acceptedMutationIds };
} });
