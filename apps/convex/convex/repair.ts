import { internalMutation } from "./_generated/server";
import { addChange } from "./lib";
import { validateSyncValue } from "./syncValue";

function isValidAccount(id: string, value: unknown) {
  try { validateSyncValue("account", id, value); return true; } catch { return false; }
}

/**
 * Older servers replaced the stored account with partial upserts (EasyCard sends only
 * `{ id, balance, updatedAt }`), dropping name/institution/kind. Rebuild those accounts by
 * folding their change history, then publish the full value so clients get a decodable record.
 *
 * Run once: `bunx convex run repair:partialAccounts`
 */
export const partialAccounts = internalMutation({ args: {}, handler: async (ctx) => {
  const repaired: string[] = [];
  for (const account of await ctx.db.query("accounts").collect()) {
    if (isValidAccount(account.externalId, account.value)) continue;
    const changes = await ctx.db.query("changes").withIndex("by_user_sequence", (q) => q.eq("userId", account.userId)).collect();
    let value: Record<string, unknown> = {};
    for (const change of changes) {
      if (change.entity !== "account" || change.entityId !== account.externalId) continue;
      value = change.action === "delete" ? {} : { ...value, ...change.value };
    }
    value = { ...value, ...account.value };
    if (!isValidAccount(account.externalId, value)) continue;
    await ctx.db.patch(account._id, { value, version: account.version + 1 });
    await addChange(ctx, account.userId, "account", account.externalId, "upsert", value);
    repaired.push(account.externalId);
  }
  return { repaired };
} });
