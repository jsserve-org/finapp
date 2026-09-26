import { query } from "./_generated/server";
import { v } from "convex/values";
import { requireSession } from "./lib";

export const snapshot = query({
  args: { tokenHash: v.string(), now: v.number() },
  handler: async (ctx, args) => {
    const session = await requireSession(ctx, args.tokenHash, args.now);
    const [accounts, transactions, holdings] = await Promise.all([
      ctx.db.query("accounts").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect(),
      ctx.db.query("transactions").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect(),
      ctx.db.query("stockHoldings").withIndex("by_user", (q) => q.eq("userId", session.userId)).collect(),
    ]);
    return {
      accounts: accounts.map((item) => item.value),
      transactions: transactions.filter((item) => !item.deleted).map((item) => item.value),
      holdings: holdings.filter((item) => !item.deleted).map((item) => item.value),
    };
  },
});
