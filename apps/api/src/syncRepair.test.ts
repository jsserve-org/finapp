import { expect, test } from "bun:test";
import type { MutationCtx } from "../../convex/convex/_generated/server";
import { exchange } from "../../convex/convex/sync";

type Row = Record<string, unknown> & { _id: string };
const name = { name: "EasyCard", institution: "EasyCard", kind: "prepaid" };
const balance = (amountMinor: number) => ({ id: "card", balance: { amountMinor, currency: "TWD" }, updatedAt: "2026-11-06T00:00:00Z" });
const logged = (sequence: number, value: unknown, action = "upsert", entity = "account", entityId = "card") => ({ _id: `change-${sequence}`, userId: "user", sequence, entity, entityId, action, value });

function fixture(rows: { accounts?: Row[]; changes: Row[] }) {
  const tables: Record<string, Row[]> = {
    users: [{ _id: "user", nextSequence: rows.changes.length }],
    sessions: [{ _id: "session", userId: "user", tokenHash: "token", expiresAt: Date.now() + 60_000 }],
    accounts: rows.accounts ?? [], changes: rows.changes, mutations: [], transactions: [], recurringPayments: [], stockHoldings: [], stockTrades: [],
  };
  const ctx = { db: {
    query: (table: string) => ({ withIndex: (_name: string, build?: (q: unknown) => unknown) => {
      const filters: [string, unknown][] = [];
      let after = -Infinity;
      const q = {
        eq: (field: string, value: unknown) => { filters.push([field, value]); return q; },
        gt: (_field: string, value: number) => { after = value; return q; },
      };
      build?.(q);
      const matches = () => tables[table].filter((row) => filters.every(([field, value]) => row[field] === value) && (table !== "changes" || Number(row.sequence) > after));
      return { collect: async () => matches(), unique: async () => matches()[0] ?? null, take: async (count: number) => matches().slice(0, count) };
    } }),
    get: async (id: string) => Object.values(tables).flat().find((row) => row._id === id),
    patch: async (id: string, value: Record<string, unknown>) => Object.assign(Object.values(tables).flat().find((row) => row._id === id)!, value),
    insert: async (table: string, value: Record<string, unknown>) => { const id = `${table}-${tables[table].length}`; tables[table].push({ ...value, _id: id }); return id; },
  } } as unknown as MutationCtx;
  type Response = { cursor: string; changes: { sequence: number; value: unknown }[]; acceptedMutationIds: string[] };
  const handler = (exchange as unknown as { _handler: (ctx: MutationCtx, args: unknown) => Promise<Response> })._handler;
  return { tables, sync: (cursor: string, operations: unknown[] = []) => handler(ctx, { tokenHash: "token", cursor, operations, now: 1 }) };
}

test("broken log entries are rebuilt when served, keeping the balance they recorded", async () => {
  const { tables, sync } = fixture({ changes: [logged(1, balance(100)), logged(2, { ...balance(200), ...name }), logged(3, balance(300))] });
  const result = await sync("0");
  expect(result.changes.map((change) => change.value)).toEqual([
    { ...balance(100), ...name },
    { ...balance(200), ...name },
    { ...balance(300), ...name },
  ]);
  expect(tables.changes[0].value).toEqual({ ...balance(100), ...name });
  expect(result.cursor).toBe("3");
});

test("a broken stored account is repaired for clients past the broken entries, and accepts balance-only updates again", async () => {
  const { tables, sync } = fixture({
    accounts: [{ _id: "account", userId: "user", externalId: "card", version: 2, value: balance(300) }],
    changes: [logged(1, { ...balance(100), ...name }), logged(2, balance(300))],
  });
  const result = await sync("2", [{ mutationId: "easycard", entity: "account", action: "upsert", entityId: "card", value: balance(400), baseVersion: 0 }]);
  expect(result.acceptedMutationIds).toEqual(["easycard"]);
  expect(tables.accounts[0].value).toEqual({ ...balance(400), ...name });
  expect(result.changes.map((change) => change.value)).toEqual([{ ...balance(300), ...name }, { ...balance(400), ...name }]);
});

test("a change that can't be rebuilt is left alone and doesn't stop the rest of the page", async () => {
  const lostAccount = { id: "lost", balance: balance(1).balance, updatedAt: "2026-11-06T00:00:00Z" };
  const { tables, sync } = fixture({ changes: [logged(1, lostAccount, "upsert", "account", "lost"), logged(2, { ...balance(200), ...name })] });
  const result = await sync("0");
  expect(result.changes.map((change) => change.value)).toEqual([lostAccount, { ...balance(200), ...name }]);
  expect(tables.changes[0].value).toEqual(lostAccount);
});

test("a delete resets what the entry was, so old fields only fill real gaps", async () => {
  const { sync } = fixture({ changes: [logged(1, { ...balance(100), ...name, kind: "old" }), logged(2, null, "delete"), logged(3, balance(300)), logged(4, { ...balance(400), ...name })] });
  const result = await sync("0");
  expect(result.changes[2].value).toEqual({ ...balance(300), ...name });
});
