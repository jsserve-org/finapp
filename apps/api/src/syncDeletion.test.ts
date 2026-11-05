import { expect, it } from "bun:test";
import type { MutationCtx } from "../../convex/convex/_generated/server";
import { exchange } from "../../convex/convex/sync";

it("acknowledges a missing transaction deletion without deleting another record", async () => {
  const inserted: unknown[] = [];
  const query = (table: string) => ({
    withIndex: () => ({
      unique: async () => table === "sessions" ? { userId: "user", expiresAt: Date.now() + 60_000 } : null,
      take: async () => [],
      collect: async () => [],
    }),
  });
  const ctx = { db: { query, insert: async (_table: string, value: unknown) => { inserted.push(value); } } } as unknown as MutationCtx;
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<{ acceptedMutationIds: string[] }> })._handler;
  const result = await handler(ctx, { tokenHash: "token", now: 1, cursor: "0", operations: [{ mutationId: "delete-missing", entity: "transaction", action: "delete", entityId: "missing", baseVersion: 0 }] });
  expect(result.acceptedMutationIds).toEqual(["delete-missing"]);
  expect(inserted).toEqual([{ userId: "user", mutationId: "delete-missing" }]);
});
