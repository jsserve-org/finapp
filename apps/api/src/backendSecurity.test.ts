import { expect, it } from "bun:test";
import type { MutationCtx } from "../../convex/convex/_generated/server";
import { requireSession } from "../../convex/convex/lib";
import { validateSession } from "../../convex/convex/auth";
import * as apiKeys from "../../convex/convex/apiKeys";
import { exchange } from "../../convex/convex/sync";

function handler<Result>(fn: unknown) {
  return (fn as { _handler: (ctx: MutationCtx, args: unknown) => Promise<Result> })._handler;
}

function context(rows: Record<string, unknown[]>) {
  const patches: { id: string; value: unknown }[] = [];
  const inserts: { table: string; value: unknown }[] = [];
  const ctx = { db: {
    query: (table: string) => ({ withIndex: () => ({
      unique: async () => rows[table]?.[0] ?? null,
      collect: async () => rows[table] ?? [],
      take: async () => [],
    }) }),
    get: async () => ({ _id: "user", username: "tester", nextSequence: 0 }),
    patch: async (id: string, value: unknown) => { patches.push({ id, value }); },
    insert: async (table: string, value: unknown) => { inserts.push({ table, value }); return "inserted"; },
    delete: async () => {},
  } } as unknown as MutationCtx;
  return { ctx, patches, inserts };
}

it("rejects expired sessions even with a forged client time", async () => {
  const { ctx } = context({ sessions: [{ userId: "user", expiresAt: 1000 }] });
  await expect(requireSession(ctx, "expired", 0)).rejects.toThrow("UNAUTHORIZED");
  expect(await handler(validateSession)(ctx, { tokenHash: "expired", now: 0 })).toBeNull();
});

it("denies automation keys all key management actions before writes", async () => {
  for (const fn of [apiKeys.list, apiKeys.create, apiKeys.revoke]) {
    const { ctx, inserts, patches } = context({ apiKeys: [{ _id: "key", userId: "user" }] });
    await expect(handler(fn)(ctx, { tokenHash: "automation", now: 0, name: "new", keyHash: "hash", prefix: "prefix", id: "key" })).rejects.toThrow("FORBIDDEN_API_KEY_MANAGEMENT");
    expect(inserts).toEqual([]);
    expect(patches).toEqual([]);
  }
});

it("allows a current user session to create a key using server time", async () => {
  const { ctx, inserts } = context({ sessions: [{ userId: "user", expiresAt: Date.now() + 60_000 }] });
  const result = await handler<{ createdAt: number }>(apiKeys.create)(ctx, { tokenHash: "session", now: 0, name: "new", keyHash: "hash", prefix: "prefix" });
  expect(result.createdAt).toBeGreaterThan(0);
  expect(inserts).toHaveLength(1);
});

it("unlinks stock trades and emits their changes when deleting an account", async () => {
  const { ctx, patches, inserts } = context({
    sessions: [{ userId: "user", expiresAt: Date.now() + 60_000 }],
    accounts: [{ _id: "account", externalId: "acc1" }],
    stockTrades: [{ _id: "trade", externalId: "trade1", version: 2, value: { id: "trade1", linkedAccountId: "acc1" } }],
  });
  await handler(exchange)(ctx, { tokenHash: "session", now: Date.now(), cursor: "0", operations: [{ mutationId: "delete", entity: "account", action: "delete", entityId: "acc1", baseVersion: 0 }] });
  expect(patches).toContainEqual({ id: "trade", value: { value: { id: "trade1", linkedAccountId: null, updatedAt: expect.any(String) }, version: 3 } });
  expect(inserts).toContainEqual({ table: "changes", value: { userId: "user", sequence: 1, entity: "stockTrade", entityId: "trade1", action: "upsert", value: { id: "trade1", linkedAccountId: null, updatedAt: expect.any(String) } } });
});
