import { expect, test } from "bun:test";
import type { MutationCtx } from "../../convex/convex/_generated/server";
import type { Id } from "../../convex/convex/_generated/dataModel";
import { belongsToOccurrence, generateForUser, linkPayment, nextOccurrence } from "../../convex/convex/recurring";
import { exchange } from "../../convex/convex/sync";
import { create as createBill } from "../../convex/convex/bills";

type Row = Record<string, unknown> & { _id: string };
function fixture() {
  const rows: Record<string, Row[]> = {
    users: [{ _id: "user", nextSequence: 0 }],
    accounts: [{ _id: "account", userId: "user", externalId: "cash", value: { balance: { amountMinor: 10000, currency: "TWD" } } }],
    recurringPayments: [{ _id: "bill", userId: "user", externalId: "netflix", version: 1, deleted: false, value: { name: "Netflix", accountId: "cash", currency: "USD", amountMinor: 1500, frequency: "monthly", nextDate: "2026-01-31T00:00:00+08:00", category: "Entertainment", isActive: true } }],
    transactions: [], changes: [], mutations: [], sessions: [{ _id: "session", userId: "user", tokenHash: "fixture", expiresAt: Date.now() + 60_000 }],
  };
  const ctx = { db: {
    query: (table: string) => ({ withIndex: (_name: string, callback: (q: { eq: (field: string, value: unknown) => unknown }) => void) => {
      const filters: [string, unknown][] = [];
      let after = -1;
      const q = {
        eq: (field: string, value: unknown) => { filters.push([field, value]); return q; },
        gt: (_field: string, value: number) => { after = value; return q; },
      };
      callback(q);
      const matches = () => (rows[table] ?? []).filter((row) => filters.every(([key, value]) => row[key] === value));
      return { collect: async () => matches(), unique: async () => matches()[0] ?? null, take: async (count: number) => matches().filter((row) => Number(row.sequence) > after).slice(0, count) };
    } }),
    get: async (id: string) => Object.values(rows).flat().find((row) => row._id === id),
    patch: async (id: string, value: Record<string, unknown>) => Object.assign(Object.values(rows).flat().find((row) => row._id === id)!, value),
    insert: async (table: string, value: Record<string, unknown>) => { const id = `${table}-${rows[table].length}`; rows[table].push({ ...value, _id: id }); return id; },
  } } as unknown as MutationCtx;
  return { ctx, rows, userId: "user" as Id<"users"> };
}

test("server subscriptions catch up once, preserve month-end dates, and do not debit cash", async () => {
  const { ctx, rows, userId } = fixture();
  const now = Date.parse("2026-02-28T01:00:00+08:00");
  await generateForUser(ctx, userId, now);
  await generateForUser(ctx, userId, now);
  expect(rows.transactions).toHaveLength(2);
  expect(rows.accounts[0].value).toEqual({ balance: { amountMinor: 10000, currency: "TWD" } });
  expect(rows.transactions[0].value).toMatchObject({ pending: true, recurringPaymentId: "netflix", source: "subscription", amount: { amountMinor: 0, currency: "TWD" } });
  expect(nextOccurrence(new Date("2026-02-28T00:00:00+08:00"), "monthly", 31).toISOString()).toBe("2026-03-30T16:00:00.000Z");
});

test("invalid schedule anchors normalize and never create duplicate occurrence IDs", async () => {
  for (const anchor of [0, -1, 32, 1.5, "bad", null]) {
    const { ctx, rows, userId } = fixture();
    (rows.recurringPayments[0].value as Record<string, unknown>).scheduleAnchorDay = anchor;
    const now = Date.parse("2026-02-28T01:00:00+08:00");
    await generateForUser(ctx, userId, now);
    await generateForUser(ctx, userId, now);
    expect(rows.transactions).toHaveLength(2);
    expect(new Set(rows.transactions.map((row) => row.externalId)).size).toBe(2);
  }
});

test("early real payments suppress an estimate and already-linked payments reconcile estimates", async () => {
  const { ctx, rows, userId } = fixture();
  const real = { id: "real", accountId: "cash", description: "Netflix.com", amount: { amountMinor: -1500, currency: "USD" }, bookedAt: "2026-01-30T01:00:00+08:00" };
  rows.transactions.push({ _id: "real", externalId: "real", userId, version: 1, deleted: false, value: real });
  await generateForUser(ctx, userId, Date.parse("2026-01-31T01:00:00+08:00"));
  expect(rows.transactions).toHaveLength(1);
  expect(rows.transactions[0].value).toMatchObject({ recurringPaymentId: "netflix" });
  rows.transactions.push({ _id: "estimate", externalId: "estimate", userId, version: 1, deleted: false, value: { ...real, id: "estimate", recurringPaymentId: "netflix", source: "subscription", pending: true } });
  await generateForUser(ctx, userId, Date.parse("2026-01-31T01:00:00+08:00"));
  expect(rows.transactions.find((row) => row._id === "estimate")?.deleted).toBe(true);
});

test("exchange preserves an explicit unlink when an importer omits the field", async () => {
  const { ctx, rows, userId } = fixture();
  (rows.recurringPayments[0].value as Record<string, unknown>).nextDate = "2099-01-31T00:00:00+08:00";
  const value = { id: "real", accountId: "cash", description: "Netflix.com", amount: { amountMinor: -1500, currency: "USD" }, bookedAt: "2026-01-31T01:00:00+08:00", pending: false, updatedAt: "2026-01-31T01:00:00+08:00" };
  rows.transactions.push({ _id: "real", externalId: "real", userId, version: 1, deleted: false, value: { ...value, recurringPaymentId: null } });
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<unknown> })._handler;
  await handler(ctx, { tokenHash: "fixture", cursor: "0", now: Date.now(), operations: [{ mutationId: "reimport", entity: "transaction", action: "upsert", entityId: "real", value, baseVersion: 0 }] });
  expect(rows.transactions[0].value).toMatchObject({ recurringPaymentId: null });
});

test("an imported payment links and removes its expected record", async () => {
  const { ctx, rows, userId } = fixture();
  await generateForUser(ctx, userId, Date.parse("2026-01-31T00:00:00+08:00"));
  const linked = await linkPayment(ctx, userId, { id: "real", accountId: "cash", description: "Netflix.com", bookedAt: "2026-01-31T10:00:00+08:00", amount: { amountMinor: -48000, currency: "TWD" }, originalAmount: { amountMinor: -1500, currency: "USD" } });
  expect(linked).toMatchObject({ recurringPaymentId: "netflix" });
  expect(rows.transactions[0].deleted).toBe(true);
  expect(rows.changes.some((row) => row.action === "delete")).toBe(true);
});

test("paused subscriptions generate nothing and historical matching payments avoid duplicate estimates", async () => {
  const { ctx, rows, userId } = fixture();
  const bill = rows.recurringPayments[0].value as Record<string, unknown>;
  bill.isActive = false;
  await generateForUser(ctx, userId, Date.parse("2026-01-31T10:00:00+08:00"));
  expect(rows.transactions).toHaveLength(0);
  bill.isActive = true;
  rows.transactions.push({ _id: "real", externalId: "real", userId, deleted: false, version: 1, value: { id: "real", accountId: "cash", description: "Netflix.com", amount: { amountMinor: -1500, currency: "USD" }, bookedAt: "2026-01-31T01:00:00+08:00" } });
  await generateForUser(ctx, userId, Date.parse("2026-01-31T10:00:00+08:00"));
  expect(rows.transactions).toHaveLength(1);
  expect(rows.transactions[0].value).toMatchObject({ recurringPaymentId: "netflix" });
});

test("monthly early and late payments satisfy their billing occurrence without phantom estimates", async () => {
  for (const bookedAt of ["2026-01-26T00:00:00+08:00", "2026-02-05T00:00:00+08:00"]) {
    const { ctx, rows, userId } = fixture();
    const value = { id: "real", accountId: "cash", description: "Netflix.com", amount: { amountMinor: -1500, currency: "USD" }, bookedAt, recurringPaymentId: "netflix" };
    rows.transactions.push({ _id: "real", externalId: "real", userId, version: 1, deleted: false, value });
    await generateForUser(ctx, userId, Date.parse("2026-02-06T00:00:00+08:00"));
    expect(rows.transactions.filter((row) => !row.deleted)).toHaveLength(1);
    const due = new Date("2026-01-31T00:00:00+08:00");
    expect(belongsToOccurrence(new Date(bookedAt), due, "monthly", 31)).toBe(true);
    expect(belongsToOccurrence(new Date("2026-02-20T00:00:00+08:00"), due, "monthly", 31)).toBe(false);
  }
});

test("a late recorded payment replaces an existing estimate", async () => {
  const { ctx, rows, userId } = fixture();
  await generateForUser(ctx, userId, Date.parse("2026-01-31T00:00:00+08:00"));
  await linkPayment(ctx, userId, { id: "late", accountId: "cash", description: "Netflix.com", amount: { amountMinor: -1500, currency: "USD" }, bookedAt: "2026-02-05T00:00:00+08:00" });
  expect(rows.transactions[0].deleted).toBe(true);
});

test("malformed accounts are skipped without aborting generation", async () => {
  for (const value of [{}, { balance: null }, { balance: {} }]) {
    const { ctx, rows, userId } = fixture();
    rows.accounts[0].value = value;
    await generateForUser(ctx, userId, Date.parse("2026-02-06T00:00:00+08:00"));
    expect(rows.transactions).toHaveLength(0);
    rows.accounts[0].value = { balance: { amountMinor: 0, currency: "TWD" } };
    await generateForUser(ctx, userId, Date.parse("2026-02-06T00:00:00+08:00"));
    expect(rows.transactions).toHaveLength(1);
  }
});

test("matching requires a merchant token rather than an amount-only or substring coincidence", async () => {
  const { ctx, userId } = fixture();
  for (const description of ["DisneyPlus.com", "NetflixExtra"]) {
    const linked = await linkPayment(ctx, userId, { id: "real", accountId: "cash", description, amount: { amountMinor: -1500, currency: "USD" }, bookedAt: "2026-01-31T10:00:00+08:00", category: "Entertainment" });
    expect(linked.recurringPaymentId).toBeUndefined();
  }
});

test("malformed schedule date types never generate or advance bills", async () => {
  for (const nextDate of [null, false, true, {}, [], "bad", "0", "2026", "2026-02", "2026-02-30T00:00:00+08:00"]) {
    const { ctx, rows, userId } = fixture();
    (rows.recurringPayments[0].value as Record<string, unknown>).nextDate = nextDate;
    await generateForUser(ctx, userId, Date.now());
    expect(rows.transactions).toHaveLength(0);
    expect(rows.changes).toHaveLength(0);
  }
});

test("late imports cannot restore transaction tombstones or missing-account history", async () => {
  for (const deleted of [true, false]) {
    const { ctx, rows, userId } = fixture();
    (rows.recurringPayments[0].value as Record<string, unknown>).isActive = false;
    const value = { id: "real", accountId: "cash", description: "Netflix", amount: { amountMinor: -1500, currency: "USD" }, bookedAt: "2026-01-31T00:00:00Z" };
    rows.transactions.push({ _id: "real", externalId: "real", userId, version: 1, deleted: true, value: deleted ? null : value });
    if (!deleted) rows.accounts.length = 0;
    const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<{ acceptedMutationIds: string[] }> })._handler;
    const result = await handler(ctx, { tokenHash: "fixture", cursor: "0", now: Date.now(), operations: [{ mutationId: "late", entity: "transaction", action: "upsert", entityId: "real", value, baseVersion: 0 }] });
    expect(result.acceptedMutationIds).toEqual(["late"]);
    expect(rows.transactions[0].deleted).toBe(true);
    expect(rows.changes).toContainEqual(expect.objectContaining({ entityId: "real", action: "delete" }));
  }
});

test("bill deletion removes estimates and retains unlinked actual payment history", async () => {
  const { ctx, rows, userId } = fixture();
  await generateForUser(ctx, userId, Date.parse("2026-01-31T00:00:00+08:00"));
  rows.transactions.push({ _id: "actual", userId, externalId: "actual", deleted: false, version: 1, value: { id: "actual", recurringPaymentId: "netflix", amount: { amountMinor: -1500, currency: "USD" } } });
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<unknown> })._handler;
  await handler(ctx, { tokenHash: "fixture", cursor: "0", now: Date.now(), operations: [{ mutationId: "delete-bill", entity: "recurringPayment", action: "delete", entityId: "netflix", baseVersion: 0 }] });
  expect(rows.transactions[0].deleted).toBe(true);
  expect(rows.transactions[1]).toMatchObject({ deleted: false, value: { recurringPaymentId: null } });
});

test("changing the schedule replaces stale estimates rather than counting them as payments", async () => {
  const { ctx, rows, userId } = fixture();
  (rows.recurringPayments[0].value as Record<string, unknown>).nextDate = "2099-01-31T00:00:00+08:00";
  await generateForUser(ctx, userId, Date.parse("2099-01-31T00:00:00+08:00"));
  const value = { ...(rows.recurringPayments[0].value as Record<string, unknown>), id: "netflix", nextDate: "2099-02-15T00:00:00+08:00", scheduleAnchorDay: 15 };
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<unknown> })._handler;
  await handler(ctx, { tokenHash: "fixture", cursor: "0", now: Date.now(), operations: [{ mutationId: "reschedule", entity: "recurringPayment", action: "upsert", entityId: "netflix", value, baseVersion: 0 }] });
  await generateForUser(ctx, userId, Date.parse("2099-02-16T00:00:00+08:00"));
  expect(rows.transactions.filter((row) => !row.deleted)).toHaveLength(1);
  expect(rows.transactions.find((row) => !row.deleted)?.value).toMatchObject({ bookedAt: "2099-02-14T16:00:00.000Z" });
});

test("resuming a paused server bill does not backfill its paused months", async () => {
  const { ctx, rows } = fixture();
  const value = rows.recurringPayments[0].value as Record<string, unknown>;
  value.isActive = false;
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<unknown> })._handler;
  await handler(ctx, { tokenHash: "fixture", cursor: "0", now: Date.now(), operations: [{ mutationId: "resume", entity: "recurringPayment", action: "upsert", entityId: "netflix", value: { ...value, id: "netflix", isActive: true }, baseVersion: 0 }] });
  expect(rows.transactions.length).toBeLessThanOrEqual(1);
  expect(rows.transactions.every((row) => Date.parse(String((row.value as Record<string, unknown>).bookedAt)) > Date.now() - 60_000)).toBe(true);
});

test("bill creation with an existing external ID cannot duplicate or debit twice", async () => {
  const { ctx, rows, userId } = fixture();
  rows.transactions.push({ _id: "existing", userId, externalId: "existing", value: { id: "existing" } });
  const handler = (createBill as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<unknown> })._handler;
  expect(await handler(ctx, { tokenHash: "fixture", now: Date.now(), bill: { id: "existing", type: "oneTime", accountId: "cash", amountMinor: 100, currency: "TWD" } })).toEqual({ id: "existing", created: false });
  expect(rows.transactions).toHaveLength(1);
  expect(rows.accounts[0].value).toMatchObject({ balance: { amountMinor: 10000 } });
});

test("partial balance updates preserve concurrent account metadata", async () => {
  const { ctx, rows } = fixture();
  (rows.recurringPayments[0].value as Record<string, unknown>).isActive = false;
  rows.accounts[0].value = { id: "cash", name: "Renamed on iPhone", institution: "Personal", kind: "cash", balance: { amountMinor: 10000, currency: "TWD" }, updatedAt: "2026-01-31T01:00:00+08:00" };
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<unknown> })._handler;
  await handler(ctx, { tokenHash: "fixture", cursor: "0", now: Date.now(), operations: [{ mutationId: "balance", entity: "account", action: "upsert", entityId: "cash", value: { id: "cash", balance: { amountMinor: 20000, currency: "TWD" } }, baseVersion: 0 }] });
  expect(rows.accounts[0].value).toMatchObject({ name: "Renamed on iPhone", institution: "Personal", balance: { amountMinor: 20000 } });
});

test("malformed sync records fail explicitly before entering the change feed", async () => {
  const samples = [
    { entity: "recurringPayment", entityId: "netflix", value: { id: "netflix", nextDate: "garbage" } },
    { entity: "recurringPayment", entityId: "netflix", value: { id: "netflix", frequency: "banana" } },
    { entity: "recurringPayment", entityId: "netflix", value: { id: "wrong" } },
    { entity: "recurringPayment", entityId: "netflix" },
    { entity: "account", entityId: "cash", value: { id: "cash", balance: "bad" } },
    { entity: "transaction", entityId: "new", value: { id: "new", accountId: "cash", description: "Bad", amount: { amountMinor: -100, currency: "TWD" }, bookedAt: "bad", pending: false, updatedAt: "2026-01-31T00:00:00Z" } },
    { entity: "stockHolding", entityId: "stock", value: { id: "stock", quantity: "bad" } },
    { entity: "stockTrade", entityId: "trade" },
  ];
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<unknown> })._handler;
  for (const sample of samples) {
    const { ctx, rows } = fixture();
    await expect(handler(ctx, { tokenHash: "fixture", cursor: "0", now: Date.now(), operations: [{ ...sample, mutationId: "malformed", action: "upsert", baseVersion: 0 }] })).rejects.toThrow("INVALID_SYNC_VALUE");
    expect(rows.changes).toHaveLength(0);
    expect(rows.mutations).toHaveLength(0);
  }
});

test("stale full automation payloads cannot undo explicit unlinks or remove estimates", async () => {
  const { ctx, rows, userId } = fixture();
  rows.sessions.length = 0;
  rows.apiKeys = [{ _id: "key", userId, tokenHash: "fixture" }];
  (rows.recurringPayments[0].value as Record<string, unknown>).nextDate = "2099-01-31T00:00:00+08:00";
  const value = { id: "real", accountId: "cash", description: "Netflix", amount: { amountMinor: -1500, currency: "USD" }, bookedAt: "2026-01-31T00:00:00Z", pending: false, updatedAt: "2026-01-31T00:00:00Z" };
  rows.transactions.push({ _id: "real", userId, externalId: "real", value: { ...value, recurringPaymentId: null }, deleted: false, version: 1 });
  rows.transactions.push({ _id: "estimate", userId, externalId: "estimate", value: { ...value, id: "estimate", source: "subscription", pending: true, recurringPaymentId: "netflix" }, deleted: false, version: 1 });
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<unknown> })._handler;
  await handler(ctx, { tokenHash: "fixture", cursor: "0", now: Date.now(), operations: [{ mutationId: "stale", entity: "transaction", entityId: "real", action: "upsert", value: { ...value, recurringPaymentId: "netflix" }, baseVersion: 0 }] });
  expect(rows.transactions[0].value).toMatchObject({ recurringPaymentId: null });
  expect(rows.transactions[1].deleted).toBe(false);
});
