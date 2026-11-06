import type { MutationCtx } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { addChange } from "./lib";
import { validateSyncValue } from "./syncValue";

function isValid(entity: string, id: string, value: unknown) {
  try { validateSyncValue(entity, id, value); return true; } catch { return false; }
}

/** Every logged change of one record, oldest first. */
function loadHistory(ctx: MutationCtx, userId: Id<"users">, entity: string, entityId: string) {
  return ctx.db.query("changes").withIndex("by_user_entity", (q) => q.eq("userId", userId).eq("entity", entity).eq("entityId", entityId)).collect();
}

/** The record as of `sequence`, with any gaps filled in from its other logged values. */
function rebuild(history: Doc<"changes">[], sequence: number) {
  const known: Record<string, unknown> = {};
  let asOf: Record<string, unknown> = {};
  for (const change of history) {
    if (change.action === "delete") {
      if (change.sequence <= sequence) asOf = {};
      continue;
    }
    Object.assign(known, change.value);
    if (change.sequence <= sequence) Object.assign(asOf, change.value);
  }
  return { ...known, ...asOf };
}

/**
 * Older servers stored partial account upserts (EasyCard sends only `{ id, balance, updatedAt }`),
 * dropping name/institution/kind. Rebuild broken accounts so new upserts can merge onto them,
 * and publish the full value for clients already past the broken log entries.
 */
export async function repairAccounts(ctx: MutationCtx, userId: Id<"users">) {
  for (const account of await ctx.db.query("accounts").withIndex("by_user", (q) => q.eq("userId", userId)).collect()) {
    if (isValid("account", account.externalId, account.value)) continue;
    const value = { ...rebuild(await loadHistory(ctx, userId, "account", account.externalId), Infinity), ...account.value };
    if (!isValid("account", account.externalId, value)) continue;
    await ctx.db.patch(account._id, { value, version: account.version + 1 });
    await addChange(ctx, userId, "account", account.externalId, "upsert", value);
  }
}

/**
 * Clients read the log in order and can stop at a record they fail to decode, so fix broken
 * entries in place as they're served. Entries that can't be rebuilt stay as they are, because
 * the validator is stricter than the clients and they may still decode.
 */
export async function repairChanges(ctx: MutationCtx, userId: Id<"users">, changes: Doc<"changes">[]) {
  const histories = new Map<string, Doc<"changes">[]>();
  for (const change of changes) {
    if (change.action !== "upsert" || isValid(change.entity, change.entityId, change.value)) continue;
    const key = `${change.entity}:${change.entityId}`;
    const history = histories.get(key) ?? await loadHistory(ctx, userId, change.entity, change.entityId);
    histories.set(key, history);
    const value = rebuild(history, change.sequence);
    if (!isValid(change.entity, change.entityId, value)) {
      console.warn(`Can't repair sync change ${change.sequence}: ${change.entity} ${change.entityId}`);
      continue;
    }
    await ctx.db.patch(change._id, { value });
    change.value = value;
  }
}
