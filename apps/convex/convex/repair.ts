import { internalMutation } from "./_generated/server";
import { addChange } from "./lib";
import { validateSyncValue } from "./syncValue";

function isValidAccount(id: string, value: unknown) {
  try { validateSyncValue("account", id, value); return true; } catch { return false; }
}

/**
 * Older servers replaced the stored account with partial upserts (EasyCard sends only
 * `{ id, balance, updatedAt }`), dropping name/institution/kind. Those partial values also
 * sit in the change log, where clients that read the log in order fail to decode them.
 * Rebuild every partial account change from the history around it, then repair the stored
 * account and publish its full value.
 *
 * Run once: `bunx convex run repair:partialAccounts`
 */
export const partialAccounts = internalMutation({ args: {}, handler: async (ctx) => {
  const repairedChanges: number[] = [];
  const repairedAccounts: string[] = [];
  for (const user of await ctx.db.query("users").collect()) {
    const changes = (await ctx.db.query("changes").withIndex("by_user_sequence", (q) => q.eq("userId", user._id)).collect())
      .filter((change) => change.entity === "account");
    // Full value of each account (folding every upsert), used to fill gaps in earlier partial changes.
    const latest = new Map<string, Record<string, unknown>>();
    for (const change of changes) {
      if (change.action === "upsert") latest.set(change.entityId, { ...latest.get(change.entityId), ...change.value });
    }
    const running = new Map<string, Record<string, unknown>>();
    for (const change of changes) {
      if (change.action === "delete") { running.delete(change.entityId); continue; }
      const value = { ...running.get(change.entityId), ...change.value };
      running.set(change.entityId, value);
      if (isValidAccount(change.entityId, change.value)) continue;
      const filled = { ...latest.get(change.entityId), ...value };
      if (!isValidAccount(change.entityId, filled)) continue;
      await ctx.db.patch(change._id, { value: filled });
      repairedChanges.push(change.sequence);
    }
    for (const account of await ctx.db.query("accounts").withIndex("by_user", (q) => q.eq("userId", user._id)).collect()) {
      if (isValidAccount(account.externalId, account.value)) continue;
      const value = { ...latest.get(account.externalId), ...account.value };
      if (!isValidAccount(account.externalId, value)) continue;
      await ctx.db.patch(account._id, { value, version: account.version + 1 });
      await addChange(ctx, user._id, "account", account.externalId, "upsert", value);
      repairedAccounts.push(account.externalId);
    }
  }
  return { repairedChanges, repairedAccounts };
} });
