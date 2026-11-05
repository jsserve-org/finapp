import { v } from "convex/values";
import { makeFunctionReference } from "convex/server";
import { internalMutation } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { addChange } from "./lib";

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function linkPayment(ctx: MutationCtx, userId: Id<"users">, input: Record<string, unknown>, cache?: { payments: Doc<"recurringPayments">[]; transactions: Doc<"transactions">[] }) {
  if (input.source === "subscription" || input.recurringPaymentId === null || typeof input.accountId !== "string" || typeof input.bookedAt !== "string" || !Number.isFinite(Date.parse(input.bookedAt))) return input;
  const money = object(input.originalAmount) ? input.originalAmount : input.amount;
  if (!object(money) || typeof money.amountMinor !== "number" || money.amountMinor >= 0) return input;
  const amountMinor = money.amountMinor;
  const payments = cache?.payments ?? await ctx.db.query("recurringPayments").withIndex("by_user", (q) => q.eq("userId", userId)).collect();
  const words = String(input.description ?? "").toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((word) => word.length >= 3);
  const matches = payments.filter((payment) => {
    const merchantWords = String(payment.value?.name ?? "").toLowerCase().split(/[^\p{L}\p{N}]+/u).filter((word) => word.length >= 3);
    return !payment.deleted && payment.value?.isActive && payment.value.accountId === input.accountId && (typeof input.recurringPaymentId === "string" ? payment.externalId === input.recurringPaymentId : payment.value.currency === money.currency && payment.value.amountMinor === -amountMinor && words.some((word) => merchantWords.includes(word)));
  });
  if (matches.length !== 1) return input;
  const payment = matches[0];
  const transactions = cache?.transactions ?? await ctx.db.query("transactions").withIndex("by_user", (q) => q.eq("userId", userId)).collect();
  const placeholders = transactions.filter((item) => !item.deleted && item.externalId !== input.id && item.value?.source === "subscription" && item.value.pending && item.value.recurringPaymentId === payment.externalId && belongsToOccurrence(new Date(String(input.bookedAt)), new Date(item.value.bookedAt), payment.value.frequency, payment.value.scheduleAnchorDay));
  if (placeholders.length > 1) return input;
  for (const item of placeholders) {
    await ctx.db.patch(item._id, { deleted: true, version: item.version + 1 });
    item.deleted = true;
    await addChange(ctx, userId, "transaction", item.externalId, "delete", null);
  }
  return { ...input, recurringPaymentId: payment.externalId };
}

const referenceEpoch = Date.UTC(2001, 0, 1);
export function recurringDate(value: unknown): Date | undefined {
  if (typeof value === "number") {
    const date = new Date(referenceEpoch + value * 1000);
    return Number.isFinite(date.getTime()) ? date : undefined;
  }
  if (typeof value !== "string") return;
  const parts = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})$/);
  if (!parts) return;
  const [, year, month, day, hour, minute, second] = parts;
  const date = new Date(value);
  const lastDay = new Date(Date.UTC(Number(year), Number(month), 0)).getUTCDate();
  if (Number(month) < 1 || Number(month) > 12 || Number(day) < 1 || Number(day) > lastDay || Number(hour) > 23 || Number(minute) > 59 || Number(second) > 59 || !Number.isFinite(date.getTime())) return;
  return date;
}
function validAnchor(anchor: unknown, date: Date): number {
  return typeof anchor === "number" && Number.isInteger(anchor) && anchor >= 1 && anchor <= 31 ? anchor : new Date(date.getTime() + 8 * 3600_000).getUTCDate();
}
export function nextOccurrence(date: Date, frequency: string, anchorDay = new Date(date.getTime() + 8 * 3600_000).getUTCDate(), direction: 1 | -1 = 1): Date {
  anchorDay = validAnchor(anchorDay, date);
  const next = new Date(date.getTime() + 8 * 3600_000);
  if (frequency === "weekly" || frequency === "everyTwoWeeks") next.setUTCDate(next.getUTCDate() + direction * (frequency === "weekly" ? 7 : 14));
  else {
    const months = frequency === "monthly" ? 1 : frequency === "yearly" ? 12 : frequency === "everyTwoYears" ? 24 : 0;
    if (!months) throw new Error("Invalid recurring frequency");
    next.setUTCDate(1);
    next.setUTCMonth(next.getUTCMonth() + direction * months);
    const lastDay = new Date(Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0)).getUTCDate();
    next.setUTCDate(Math.min(anchorDay, lastDay));
  }
  return new Date(next.getTime() - 8 * 3600_000);
}

export function belongsToOccurrence(booked: Date, due: Date, frequency: string, anchorDay?: number): boolean {
  if (!["weekly", "everyTwoWeeks", "monthly", "yearly", "everyTwoYears"].includes(frequency) || !Number.isFinite(due.getTime())) return false;
  const anchor = validAnchor(anchorDay, due);
  const previous = nextOccurrence(due, frequency, anchor, -1);
  const next = nextOccurrence(due, frequency, anchor);
  const start = (previous.getTime() + due.getTime()) / 2;
  const end = (due.getTime() + next.getTime()) / 2;
  return booked.getTime() >= start && booked.getTime() < end;
}

export async function generateForUser(ctx: MutationCtx, userId: Id<"users">, now: number) {
  const payments = await ctx.db.query("recurringPayments").withIndex("by_user", (q) => q.eq("userId", userId)).collect();
  const transactions = await ctx.db.query("transactions").withIndex("by_user", (q) => q.eq("userId", userId)).collect();
  for (const transaction of transactions) {
    if (transaction.deleted || !object(transaction.value) || transaction.value.recurringPaymentId === null || transaction.value.source === "subscription") continue;
    const linked = await linkPayment(ctx, userId, transaction.value, { payments, transactions });
    if (linked.recurringPaymentId && linked.recurringPaymentId !== transaction.value.recurringPaymentId) {
      transaction.value = linked;
      await ctx.db.patch(transaction._id, { value: linked, version: transaction.version + 1 });
      await addChange(ctx, userId, "transaction", transaction.externalId, "upsert", linked);
    }
  }
  for (const payment of payments) {
    const value = payment.value;
    if (payment.deleted || !value?.isActive || !value.accountId || !Number.isSafeInteger(value.amountMinor) || value.amountMinor <= 0 || !["weekly", "everyTwoWeeks", "monthly", "yearly", "everyTwoYears"].includes(value.frequency)) continue;
    const account = await ctx.db.query("accounts").withIndex("by_user_external", (q) => q.eq("userId", userId).eq("externalId", value.accountId)).unique();
    if (!account || !object(account.value) || !object(account.value.balance) || typeof account.value.balance.currency !== "string") continue;
    let due = recurringDate(value.nextDate);
    if (!due || due.getTime() > now) continue;
    const anchorDay = validAnchor(value.scheduleAnchorDay, due);
    let count = 0;
    while (due.getTime() <= now && count++ < 36) {
      const next = nextOccurrence(due, value.frequency, anchorDay);
      if (!Number.isFinite(next.getTime()) || next.getTime() <= due.getTime()) break;
      const id = `subscription-${payment.externalId}-${due.getTime()}`;
      const recorded = transactions.some((item) => item.externalId === id || (!item.deleted && item.value?.source !== "subscription" && item.value?.recurringPaymentId === payment.externalId && belongsToOccurrence(new Date(item.value.bookedAt), due!, value.frequency, anchorDay)));
      if (!recorded) {
        const transaction = { id, accountId: value.accountId, description: value.name,
          amount: { amountMinor: 0, currency: account.value.balance.currency },
          originalAmount: { amountMinor: -value.amountMinor, currency: value.currency },
          bookedAt: due.toISOString(), pending: true, category: value.category,
          recurringPaymentId: payment.externalId, source: "subscription", updatedAt: new Date(now).toISOString() };
        const record = { userId, externalId: id, value: transaction, version: 1, deleted: false };
        const inserted = await ctx.db.insert("transactions", record);
        transactions.push({ ...record, _id: inserted, _creationTime: now });
        await addChange(ctx, userId, "transaction", id, "upsert", transaction);
      }
      due = next;
    }
    const updated = { ...value, nextDate: (due.getTime() - referenceEpoch) / 1000, scheduleAnchorDay: anchorDay };
    await ctx.db.patch(payment._id, { value: updated, version: payment.version + 1 });
    await addChange(ctx, userId, "recurringPayment", payment.externalId, "upsert", updated);
  }
}

export const generateDue = internalMutation({ args: { cursor: v.optional(v.string()) }, handler: async (ctx, args) => {
  const page = await ctx.db.query("users").paginate({ cursor: args.cursor ?? null, numItems: 25 });
  for (const user of page.page) await generateForUser(ctx, user._id, Date.now());
  if (!page.isDone) await ctx.scheduler.runAfter(0, makeFunctionReference<"mutation">("recurring:generateDue"), { cursor: page.continueCursor });
} });
