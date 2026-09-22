import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

declare const process: { env: Record<string, string | undefined> };

function requireGateway(secret: string) {
  if (!process.env.API_SERVICE_SECRET || secret !== process.env.API_SERVICE_SECRET) throw new Error("UNAUTHORIZED");
}

export const createUser = mutation({ args: { username: v.string(), passwordHash: v.string(), serviceSecret: v.string() }, handler: async (ctx, args) => {
  requireGateway(args.serviceSecret);
  if (await ctx.db.query("users").withIndex("by_username", (q) => q.eq("username", args.username)).unique()) throw new Error("USERNAME_TAKEN");
  return ctx.db.insert("users", { username: args.username, passwordHash: args.passwordHash, nextSequence: 0 });
} });

export const getCredential = query({ args: { username: v.string(), serviceSecret: v.string() }, handler: async (ctx, args) => {
  requireGateway(args.serviceSecret);
  const user = await ctx.db.query("users").withIndex("by_username", (q) => q.eq("username", args.username)).unique();
  return user ? { userId: user._id, passwordHash: user.passwordHash } : null;
} });

export const createSession = mutation({ args: { userId: v.id("users"), tokenHash: v.string(), expiresAt: v.number(), serviceSecret: v.string(), context: v.object({ apiUrl: v.string(), convexUrl: v.string() }) }, handler: async (ctx, args) => {
  requireGateway(args.serviceSecret);
  const syncSessionId = crypto.randomUUID();
  await ctx.db.insert("sessions", { userId: args.userId, tokenHash: args.tokenHash, expiresAt: args.expiresAt, syncSessionId, context: args.context });
  return { syncSessionId };
} });

export const validateSession = query({ args: { tokenHash: v.string(), now: v.number() }, handler: async (ctx, args) => {
  const session = await ctx.db.query("sessions").withIndex("by_token", (q) => q.eq("tokenHash", args.tokenHash)).unique();
  if (!session || session.revokedAt || session.expiresAt <= args.now) return null;
  const user = await ctx.db.get(session.userId);
  return user ? { userId: user._id, username: user.username, syncSessionId: session.syncSessionId, context: session.context } : null;
} });

export const revokeSession = mutation({ args: { tokenHash: v.string() }, handler: async (ctx, args) => {
  const session = await ctx.db.query("sessions").withIndex("by_token", (q) => q.eq("tokenHash", args.tokenHash)).unique();
  if (session) await ctx.db.patch(session._id, { revokedAt: Date.now() });
} });
