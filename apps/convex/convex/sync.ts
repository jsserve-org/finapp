import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { addChange, requireSession } from "./lib";

export const exchange = mutation({ args: { tokenHash: v.string(), cursor: v.string(), operations: v.array(v.any()), now: v.number() }, handler: async (ctx, args) => {
  const session = await requireSession(ctx, args.tokenHash, args.now);
  const acceptedMutationIds: string[] = [];
  for (const operation of args.operations.slice(0, 100)) {
    const prior = await ctx.db.query("mutations").withIndex("by_user_mutation", (q) => q.eq("userId", session.userId).eq("mutationId", operation.mutationId)).unique();
    if (prior) { acceptedMutationIds.push(operation.mutationId); continue; }
    const transaction = await ctx.db.query("transactions").withIndex("by_user_external", (q) => q.eq("userId", session.userId).eq("externalId", operation.entityId)).unique();
    if (!transaction || transaction.version !== operation.baseVersion) continue;
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
