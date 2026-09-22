import { zValidator } from "@hono/zod-validator";
import { and, asc, eq, gt, inArray } from "drizzle-orm";
import { Hono } from "hono";
import { z } from "zod";
import { db } from "../db";
import { processedMutations, syncChanges, transactions } from "../db/schema";
import { serializeTransaction } from "../domain/serializers";

const operation = z.object({
  mutationId: z.string().uuid(), entity: z.literal("transaction"), action: z.enum(["upsert", "delete"]),
  entityId: z.string().uuid(), value: z.object({ description: z.string().min(1).max(300).optional(), category: z.string().max(80).optional() }).optional(),
  baseVersion: z.number().int().nonnegative(),
});
const request = z.object({ cursor: z.string().regex(/^\d+$/).optional(), operations: z.array(operation).max(100).default([]) });

export const syncRoutes = new Hono<{ Variables: { userId: string } }>().post("/", zValidator("json", request), async (c) => {
  const userId = c.get("userId");
  const body = c.req.valid("json");
  const accepted: string[] = [];

  await db.transaction(async (tx) => {
    const ids = body.operations.map((item) => item.mutationId);
    const existing = ids.length ? await tx.select({ id: processedMutations.mutationId }).from(processedMutations).where(inArray(processedMutations.mutationId, ids)) : [];
    const alreadyDone = new Set(existing.map((item) => item.id));
    for (const op of body.operations) {
      if (alreadyDone.has(op.mutationId)) { accepted.push(op.mutationId); continue; }
      const [current] = await tx.select().from(transactions).where(and(eq(transactions.id, op.entityId), eq(transactions.userId, userId))).limit(1);
      if (!current) continue;
      if (current.version !== op.baseVersion) continue;
      const [updated] = await tx.update(transactions).set(op.action === "delete"
        ? { deletedAt: new Date(), version: current.version + 1, updatedAt: new Date() }
        : { ...op.value, version: current.version + 1, updatedAt: new Date() })
        .where(and(eq(transactions.id, op.entityId), eq(transactions.userId, userId))).returning();
      await tx.insert(syncChanges).values({ userId, entity: "transaction", entityId: updated.id, action: op.action, value: op.action === "delete" ? null : serializeTransaction(updated) });
      await tx.insert(processedMutations).values({ mutationId: op.mutationId, userId });
      accepted.push(op.mutationId);
    }
  });

  const after = Number(body.cursor ?? "0");
  const changes = await db.select().from(syncChanges).where(and(eq(syncChanges.userId, userId), gt(syncChanges.sequence, after))).orderBy(asc(syncChanges.sequence)).limit(500);
  const cursor = String(changes.at(-1)?.sequence ?? after);
  return c.json({ cursor, changes: changes.map(({ sequence, entity, entityId, action, value }) => ({ sequence, entity, entityId, action, value })), acceptedMutationIds: accepted });
});
