import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { requireSession } from "./lib";

export const list = query({
  args: { tokenHash: v.string(), now: v.number() },
  handler: async (ctx, args) => {
    const identity = await requireSession(ctx, args.tokenHash, args.now);
    const keys = await ctx.db.query("apiKeys").withIndex("by_user", (q) => q.eq("userId", identity.userId)).collect();
    return keys.filter((key) => !key.revokedAt).map((key) => ({
      id: key._id,
      name: key.name,
      prefix: key.prefix,
      createdAt: key.createdAt,
    }));
  },
});

export const create = mutation({
  args: { tokenHash: v.string(), now: v.number(), name: v.string(), keyHash: v.string(), prefix: v.string() },
  handler: async (ctx, args) => {
    const identity = await requireSession(ctx, args.tokenHash, args.now);
    const id = await ctx.db.insert("apiKeys", {
      userId: identity.userId,
      name: args.name,
      prefix: args.prefix,
      tokenHash: args.keyHash,
      createdAt: args.now,
    });
    return { id, name: args.name, prefix: args.prefix, createdAt: args.now };
  },
});

export const revoke = mutation({
  args: { tokenHash: v.string(), now: v.number(), id: v.id("apiKeys") },
  handler: async (ctx, args) => {
    const identity = await requireSession(ctx, args.tokenHash, args.now);
    const key = await ctx.db.get(args.id);
    if (!key || key.userId !== identity.userId) throw new Error("API_KEY_NOT_FOUND");
    await ctx.db.patch(args.id, { revokedAt: args.now });
  },
});
