import { z } from "zod";

export const syncRequest = z.object({
  protocolVersion: z.number().int().optional(),
  cursor: z.string().regex(/^\d+$/).refine((value) => Number.isSafeInteger(Number(value))).default("0"),
  operations: z.array(z.object({
    mutationId: z.string().min(1),
    entity: z.enum(["account", "transaction", "recurringPayment", "stockHolding", "stockTrade"]),
    action: z.enum(["upsert", "delete"]),
    entityId: z.string().min(1),
    value: z.record(z.string(), z.unknown()).optional(),
    baseVersion: z.number().int().nonnegative(),
  })).default([]),
});
