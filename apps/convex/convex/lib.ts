import type { MutationCtx, QueryCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel";

export async function requireSession(ctx: QueryCtx | MutationCtx, tokenHash: string, now: number) {
  const session = await ctx.db.query("sessions").withIndex("by_token", (q) => q.eq("tokenHash", tokenHash)).unique();
  if (!session || session.revokedAt || session.expiresAt <= now) throw new Error("UNAUTHORIZED");
  return session;
}

export async function addChange(ctx: MutationCtx, userId: Id<"users">, entity: string, entityId: string, action: string, value: unknown) {
  const user = await ctx.db.get(userId);
  if (!user) throw new Error("USER_NOT_FOUND");
  const sequence = user.nextSequence + 1;
  await ctx.db.patch(userId, { nextSequence: sequence });
  await ctx.db.insert("changes", { userId, sequence, entity, entityId, action, value });
  return sequence;
}
