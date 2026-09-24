import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

export default defineSchema({
  users: defineTable({ username: v.string(), passwordHash: v.string(), nextSequence: v.number() }).index("by_username", ["username"]),
  sessions: defineTable({ userId: v.id("users"), tokenHash: v.string(), syncSessionId: v.string(), expiresAt: v.number(), revokedAt: v.optional(v.number()), context: v.optional(v.object({ apiUrl: v.string(), convexUrl: v.string() })) }).index("by_token", ["tokenHash"]),
  apiKeys: defineTable({ userId: v.id("users"), name: v.string(), prefix: v.string(), tokenHash: v.string(), createdAt: v.number(), revokedAt: v.optional(v.number()) }).index("by_token", ["tokenHash"]).index("by_user", ["userId"]),
  accounts: defineTable({ userId: v.id("users"), externalId: v.string(), value: v.any(), version: v.number() }).index("by_user", ["userId"]).index("by_user_external", ["userId", "externalId"]),
  transactions: defineTable({ userId: v.id("users"), externalId: v.string(), value: v.any(), version: v.number(), deleted: v.boolean() }).index("by_user", ["userId"]).index("by_user_external", ["userId", "externalId"]),
  recurringPayments: defineTable({ userId: v.id("users"), externalId: v.string(), value: v.any(), version: v.number(), deleted: v.boolean() }).index("by_user", ["userId"]).index("by_user_external", ["userId", "externalId"]),
  changes: defineTable({ userId: v.id("users"), sequence: v.number(), entity: v.string(), entityId: v.string(), action: v.string(), value: v.any() }).index("by_user_sequence", ["userId", "sequence"]),
  mutations: defineTable({ userId: v.id("users"), mutationId: v.string() }).index("by_user_mutation", ["userId", "mutationId"]),
  connections: defineTable({ userId: v.id("users"), externalId: v.string(), state: v.string(), lastSuccessAt: v.optional(v.string()), lastError: v.optional(v.string()), nextCheckAt: v.string() }).index("by_user", ["userId"]).index("by_user_external", ["userId", "externalId"]),
});
