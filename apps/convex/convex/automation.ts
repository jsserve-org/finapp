import { mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { addChange, requireSession } from "./lib";

export const statuses = query({ args: { tokenHash: v.string(), now: v.number() }, handler: async (ctx, args) => {
  const session = await requireSession(ctx, args.tokenHash, args.now);
  return (await ctx.db.query("connections").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect()).map((item) => ({ connectionId: item.externalId, state: item.state, lastSuccessAt: item.lastSuccessAt, lastError: item.lastError, nextCheckAt: item.nextCheckAt }));
} });

export const runDemo = mutation({ args: { tokenHash: v.string(), now: v.number() }, handler: async (ctx, args) => {
  const session = await requireSession(ctx, args.tokenHash, args.now);
  const date = new Date(args.now).toISOString();
  const accountId = "demo-checking";
  const accountValue = { id: accountId, name: "Everyday", institution: "Demo Bank", kind: "checking", balance: { amountMinor: 245832, currency: "USD" }, updatedAt: date };
  const existing = await ctx.db.query("accounts").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", accountId)).unique();
  if (existing) await ctx.db.patch(existing._id, { value: accountValue, version: existing.version + 1 }); else await ctx.db.insert("accounts", { userId: session.userId, externalId: accountId, value: accountValue, version: 1 });
  await addChange(ctx, session.userId, "account", accountId, "upsert", accountValue);
  for (const item of [{ id: `coffee-${date.slice(0, 10)}`, description: "Corner Coffee", amount: -525 }, { id: `salary-${date.slice(0, 10)}`, description: "Salary", amount: 320000 }]) {
    const value = { id: item.id, accountId, description: item.description, amount: { amountMinor: item.amount, currency: "USD" }, bookedAt: date, pending: false, source: "automation", updatedAt: date };
    const old = await ctx.db.query("transactions").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", item.id)).unique();
    if (old) await ctx.db.patch(old._id, { value, deleted: false, version: old.version + 1 }); else await ctx.db.insert("transactions", { userId: session.userId, externalId: item.id, value, version: 1, deleted: false });
    await addChange(ctx, session.userId, "transaction", item.id, "upsert", value);
  }
  const connection = await ctx.db.query("connections").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", "demo")).unique();
  const status = { state: "healthy", lastSuccessAt: date, lastError: undefined, nextCheckAt: new Date(args.now + 15 * 60_000).toISOString() };
  if (connection) await ctx.db.patch(connection._id, status); else await ctx.db.insert("connections", { userId: session.userId, externalId: "demo", ...status });
  return { runId: crypto.randomUUID(), state: "succeeded" };
} });
