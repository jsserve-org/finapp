import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { addChange, requireSession } from "./lib";

export const listAccounts = query({
  args: { tokenHash: v.string(), now: v.number() },
  handler: async (ctx, args) => {
    const session = await requireSession(ctx, args.tokenHash, args.now);
    const accounts = await ctx.db.query("accounts").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect();
    return accounts.map((account) => account.value);
  },
});

export const create = mutation({
  args: { tokenHash: v.string(), now: v.number(), bill: v.any() },
  handler: async (ctx, args) => {
    const session = await requireSession(ctx, args.tokenHash, args.now);
    const bill = args.bill;
    const existingMutation = await ctx.db.query("mutations").withIndex("by_user_mutation", (q) => q.eq("userId", session.userId).eq("mutationId", bill.id)).unique();
    if (existingMutation) return { id: bill.id, created: false };

    if (bill.type === "oneTime") {
      const account = await ctx.db.query("accounts").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", bill.accountId)).unique();
      if (!account) throw new Error("ACCOUNT_NOT_FOUND");
      const accountCurrency = account.value?.balance?.currency;
      const isForeignCurrency = accountCurrency !== bill.currency;
      if (isForeignCurrency && !bill.settlementAmountMinor) throw new Error("SETTLEMENT_AMOUNT_REQUIRED");
      const settlementAmountMinor = bill.settlementAmountMinor ?? bill.amountMinor;
      const timestamp = new Date(args.now).toISOString();
      const transaction = {
        id: bill.id,
        accountId: bill.accountId,
        description: bill.name,
        amount: { amountMinor: -settlementAmountMinor, currency: accountCurrency },
        ...(isForeignCurrency ? { originalAmount: { amountMinor: -bill.amountMinor, currency: bill.currency } } : {}),
        bookedAt: bill.date,
        pending: false,
        category: bill.category,
        updatedAt: timestamp,
      };
      await ctx.db.insert("transactions", { userId: session.userId, externalId: bill.id, value: transaction, version: 1, deleted: false });
      await addChange(ctx, session.userId, "transaction", bill.id, "upsert", transaction);
      const accountValue = { ...account.value, balance: { ...account.value.balance, amountMinor: account.value.balance.amountMinor - settlementAmountMinor }, updatedAt: timestamp };
      await ctx.db.patch(account._id, { value: accountValue, version: account.version + 1 });
      await addChange(ctx, session.userId, "account", account.externalId, "upsert", accountValue);
    } else {
      if (bill.accountId) {
        const account = await ctx.db.query("accounts").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", bill.accountId)).unique();
        if (!account) throw new Error("ACCOUNT_NOT_FOUND");
      }
      const payment = {
        id: bill.id,
        name: bill.name,
        amountMinor: bill.amountMinor,
        currency: bill.currency,
        frequency: bill.frequency,
        nextDate: bill.nextDate,
        accountId: bill.accountId ?? null,
        category: bill.category,
        isActive: true,
      };
      await ctx.db.insert("recurringPayments", { userId: session.userId, externalId: bill.id, value: payment, version: 1, deleted: false });
      await addChange(ctx, session.userId, "recurringPayment", bill.id, "upsert", payment);
    }

    await ctx.db.insert("mutations", { userId: session.userId, mutationId: bill.id });
    return { id: bill.id, created: true };
  },
});
