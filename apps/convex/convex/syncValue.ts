import { recurringDate } from "./recurring";

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const text = (value: unknown): value is string => typeof value === "string";
const identifier = (value: unknown) => text(value) && value.length > 0;
const currency = (value: unknown) => text(value) && /^[A-Z]{3}$/.test(value);
const integer = (value: unknown) => typeof value === "number" && Number.isSafeInteger(value);
const timestamp = (value: unknown) => text(value) && recurringDate(value) !== undefined;
const money = (value: unknown) => object(value) && integer(value.amountMinor) && currency(value.currency);
const optional = (value: unknown, valid: (value: unknown) => boolean) => value == null || valid(value);

/** Validate the merged value before publishing a record that native clients must decode. */
export function validateSyncValue(entity: string, id: string, value: unknown): asserts value is Record<string, unknown> {
  const invalid = () => { throw new Error(`INVALID_SYNC_VALUE: ${entity} ${id}`); };
  if (!object(value) || value.id !== id) return invalid();
  if (entity === "account") {
    if (!text(value.name) || !text(value.institution) || !text(value.kind) || !money(value.balance) || !timestamp(value.updatedAt)) invalid();
  } else if (entity === "recurringPayment") {
    if (!text(value.name) || !integer(value.amountMinor) || Number(value.amountMinor) <= 0 || !currency(value.currency) || !["weekly", "everyTwoWeeks", "monthly", "yearly", "everyTwoYears"].includes(String(value.frequency)) || !recurringDate(value.nextDate) || !optional(value.accountId, identifier) || !text(value.category) || typeof value.isActive !== "boolean" || !optional(value.scheduleAnchorDay, integer)) invalid();
  } else if (entity === "transaction") {
    if (!identifier(value.accountId) || !text(value.description) || !money(value.amount) || !optional(value.originalAmount, money) || !timestamp(value.bookedAt) || !timestamp(value.updatedAt) || typeof value.pending !== "boolean") invalid();
    for (const field of ["category", "recurringPaymentId", "source", "expensePurpose", "reimbursementStatus", "reimbursementTransactionId", "refundTransactionId", "refundedTransactionId", "transferId", "transferAccountId", "transferDirection"]) {
      if (!optional(value[field], text)) invalid();
    }
    if (!optional(value.categoryUserEdited, (item) => typeof item === "boolean") || !optional(value.balanceImpactMinor, integer)) invalid();
  } else {
    if (!identifier(value.symbol) || !currency(value.currency) || typeof value.quantity !== "number" || !Number.isFinite(value.quantity) || value.quantity < 0 || !optional(value.linkedAccountId, identifier)) invalid();
    if (entity === "stockHolding") {
      if (!text(value.name) || !integer(value.averageCostMinor) || !integer(value.currentPriceMinor) || !timestamp(value.updatedAt)) invalid();
    } else if (entity === "stockTrade") {
      if (!identifier(value.holdingId) || !["buy", "sell"].includes(String(value.side)) || !integer(value.priceMinor) || !integer(value.feesMinor) || !timestamp(value.tradedAt)) invalid();
    } else invalid();
  }
}
