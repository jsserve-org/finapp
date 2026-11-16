import {
  cachedAccounts,
  cachedRecurringPayments,
  cachedTransactions,
  cachedVersion,
  deleteCached,
  enqueue,
  getCached,
  notifyChanged,
  putCached,
} from "./db";
import { isoNow } from "./format";
import { uuid } from "./ids";
import type { Account, RecurringPayment, Transaction, TransactionFrequency } from "./types";

export type AccountEntryDirection = "moneyIn" | "moneyOut";

export const directionDefaults = {
  moneyIn: { title: "Add money", description: "Cash deposit", category: "Deposit" },
  moneyOut: { title: "Spend money", description: "Cash expense", category: "Cash" },
} as const;

const accountDTO = (account: Account) => ({
  id: account.id,
  name: account.name,
  institution: account.institution,
  kind: account.kind,
  balance: account.balance,
  updatedAt: account.updatedAt,
});

const transactionDTO = (transaction: Transaction) => {
  const value: Record<string, unknown> = {
    id: transaction.id,
    accountId: transaction.accountId,
    description: transaction.description,
    amount: transaction.amount,
    bookedAt: transaction.bookedAt,
    pending: transaction.pending,
    category: transaction.category ?? null,
    categoryUserEdited: transaction.categoryUserEdited ?? false,
    recurringPaymentId: transaction.recurringPaymentId ?? null,
    source: transaction.source ?? null,
    expensePurpose: transaction.expensePurpose ?? null,
    reimbursementStatus: transaction.reimbursementStatus ?? null,
    reimbursementTransactionId: transaction.reimbursementTransactionId ?? null,
    refundTransactionId: transaction.refundTransactionId ?? null,
    refundedTransactionId: transaction.refundedTransactionId ?? null,
    transferId: transaction.transferId ?? null,
    transferAccountId: transaction.transferAccountId ?? null,
    transferDirection: transaction.transferDirection ?? null,
    updatedAt: transaction.updatedAt,
  };
  if (transaction.originalAmount) value.originalAmount = transaction.originalAmount;
  if (typeof transaction.balanceImpactMinor === "number") value.balanceImpactMinor = transaction.balanceImpactMinor;
  return value;
};

const recurringDTO = (payment: RecurringPayment) => ({
  id: payment.id,
  name: payment.name,
  amountMinor: payment.amountMinor,
  currency: payment.currency,
  frequency: payment.frequency,
  nextDate: payment.nextDate,
  accountId: payment.accountId ?? null,
  category: payment.category,
  isActive: payment.isActive,
  ...(payment.scheduleAnchorDay ? { scheduleAnchorDay: payment.scheduleAnchorDay } : {}),
});

const tracksAccountBalance = (transaction: Transaction) =>
  ["manual", "transfer", "screenshot", "refund", "reimbursement", "bill"].includes(transaction.source ?? "");

export const appliedBalance = (transaction: Transaction) =>
  typeof transaction.balanceImpactMinor === "number"
    ? transaction.balanceImpactMinor
    : tracksAccountBalance(transaction)
      ? transaction.amount.amountMinor
      : 0;

// MARK: - Accounts

export function createAccount(input: {
  name: string;
  institution: string;
  kind: string;
  amountMinor: number;
  currency: string;
}): Account {
  const account: Account = {
    id: uuid(),
    name: input.name.trim(),
    institution: input.institution.trim() || "Manual",
    kind: input.kind,
    balance: { amountMinor: input.amountMinor, currency: input.currency },
    updatedAt: isoNow(),
  };
  putCached("account", account.id, account, 0);
  enqueue({ entity: "account", action: "upsert", entityId: account.id, value: accountDTO(account), baseVersion: 0 });
  notifyChanged();
  return account;
}

export function updateAccount(id: string, input: { name: string; institution: string; kind: string }) {
  const account = getCached<Account>("account", id);
  if (!account) return;
  const next: Account = {
    ...account,
    name: input.name.trim(),
    institution: input.institution.trim() || "Manual",
    kind: input.kind,
    updatedAt: isoNow(),
  };
  putCached("account", id, next, cachedVersion("account", id));
  enqueue({ entity: "account", action: "upsert", entityId: id, value: accountDTO(next), baseVersion: cachedVersion("account", id) });
  notifyChanged();
}

/** Deleting an account cascades to its transactions and bills, like the native app. */
export function deleteAccount(id: string) {
  const transactions = cachedTransactions().filter((transaction) => transaction.accountId === id);
  for (const transaction of transactions) {
    deleteCached("transaction", transaction.id);
    enqueue({ entity: "transaction", action: "delete", entityId: transaction.id, value: null, baseVersion: cachedVersion("transaction", transaction.id) });
  }
  for (const payment of readRecurringForAccount(id)) {
    deleteCached("recurringPayment", payment.id);
    enqueue({ entity: "recurringPayment", action: "delete", entityId: payment.id, value: null, baseVersion: cachedVersion("recurringPayment", payment.id) });
  }
  deleteCached("account", id);
  enqueue({ entity: "account", action: "delete", entityId: id, value: null, baseVersion: cachedVersion("account", id) });
  notifyChanged();
}

function readRecurringForAccount(id: string) {
  return cachedRecurringPayments().filter((payment) => payment.accountId === id);
}

// MARK: - Money

export function recordMoney(input: {
  direction: AccountEntryDirection;
  accountId: string;
  amountMinor: number;
  currency: string;
  description: string;
  category: string;
  date: Date;
  expensePurpose?: string;
  expectsReimbursement?: boolean;
}) {
  const accounts = cachedAccounts();
  const account = accounts.find((item) => item.id === input.accountId);
  if (!account) return;

  const signedAmount = input.direction === "moneyIn" ? input.amountMinor : -input.amountMinor;
  const settlementPending = input.direction === "moneyOut" && input.currency !== account.balance.currency;
  const recordedAmount = settlementPending ? 0 : signedAmount;
  const timestamp = input.date.toISOString();

  const transaction: Transaction = {
    id: uuid(),
    accountId: account.id,
    description: input.description.trim() || directionDefaults[input.direction].description,
    amount: { amountMinor: recordedAmount, currency: account.balance.currency },
    originalAmount: settlementPending ? { amountMinor: signedAmount, currency: input.currency } : undefined,
    bookedAt: timestamp,
    pending: settlementPending,
    category: input.category.trim() || directionDefaults[input.direction].category,
    categoryUserEdited: true,
    source: "manual",
    expensePurpose: input.expensePurpose,
    reimbursementStatus: input.expectsReimbursement && input.direction === "moneyOut" ? "pending" : undefined,
    balanceImpactMinor: recordedAmount,
    updatedAt: timestamp,
  };

  putCached("transaction", transaction.id, transaction, 0);
  enqueue({ entity: "transaction", action: "upsert", entityId: transaction.id, value: transactionDTO(transaction), baseVersion: 0 });
  linkNearbyBill(transaction, readRecurring());

  if (!settlementPending) {
    const next: Account = {
      ...account,
      balance: { ...account.balance, amountMinor: account.balance.amountMinor + signedAmount },
      updatedAt: isoNow(),
    };
    putCached("account", account.id, next, cachedVersion("account", account.id));
    enqueue({ entity: "account", action: "upsert", entityId: account.id, value: accountDTO(next), baseVersion: cachedVersion("account", account.id) });
  }
  notifyChanged();
  return transaction;
}

export function transfer(input: { amountMinor: number; description: string; date: Date; sourceId: string; destinationId: string }) {
  const accounts = cachedAccounts();
  const source = accounts.find((item) => item.id === input.sourceId);
  const destination = accounts.find((item) => item.id === input.destinationId);
  if (!source || !destination) return;

  const transferId = uuid();
  const timestamp = input.date.toISOString();
  const outgoing: Transaction = {
    id: `${transferId}-out`,
    accountId: source.id,
    description: `${input.description} to ${destination.name}`,
    amount: { amountMinor: -input.amountMinor, currency: source.balance.currency },
    bookedAt: timestamp,
    pending: false,
    category: "Transfer",
    categoryUserEdited: true,
    source: "transfer",
    transferId,
    transferAccountId: destination.id,
    transferDirection: "outgoing",
    updatedAt: timestamp,
  };
  const incoming: Transaction = {
    ...outgoing,
    id: `${transferId}-in`,
    accountId: destination.id,
    description: `${input.description} from ${source.name}`,
    amount: { amountMinor: input.amountMinor, currency: source.balance.currency },
    transferAccountId: source.id,
    transferDirection: "incoming",
  };

  for (const transaction of [outgoing, incoming]) {
    putCached("transaction", transaction.id, transaction, 0);
    enqueue({ entity: "transaction", action: "upsert", entityId: transaction.id, value: transactionDTO(transaction), baseVersion: 0 });
  }

  const nextSource: Account = {
    ...source,
    balance: { ...source.balance, amountMinor: source.balance.amountMinor - input.amountMinor },
    updatedAt: isoNow(),
  };
  const nextDestination: Account = {
    ...destination,
    balance: { ...destination.balance, amountMinor: destination.balance.amountMinor + input.amountMinor },
    updatedAt: isoNow(),
  };
  for (const account of [nextSource, nextDestination]) {
    putCached("account", account.id, account, cachedVersion("account", account.id));
    enqueue({ entity: "account", action: "upsert", entityId: account.id, value: accountDTO(account), baseVersion: cachedVersion("account", account.id) });
  }
  notifyChanged();
}

export function updateTransaction(id: string, changes: { description?: string; category?: string; recurringPaymentId?: string | null }) {
  const transaction = getCached<Transaction>("transaction", id);
  if (!transaction) return;
  const next: Transaction = {
    ...transaction,
    description: changes.description?.trim() || transaction.description,
    category: changes.category ?? transaction.category,
    categoryUserEdited: changes.category != null ? true : transaction.categoryUserEdited,
    recurringPaymentId:
      changes.recurringPaymentId === undefined ? transaction.recurringPaymentId : (changes.recurringPaymentId ?? undefined),
    updatedAt: isoNow(),
  };
  putCached("transaction", id, next, cachedVersion("transaction", id));
  const value = transactionDTO(next);
  if (changes.recurringPaymentId === null) value.recurringPaymentId = null;
  enqueue({ entity: "transaction", action: "upsert", entityId: id, value, baseVersion: cachedVersion("transaction", id) });
  notifyChanged();
}

export function deleteTransaction(id: string) {
  const transaction = getCached<Transaction>("transaction", id);
  if (!transaction) return;
  const entries = transaction.transferId
    ? cachedTransactions().filter((item) => item.transferId === transaction.transferId)
    : [transaction];
  const accounts = cachedAccounts();
  for (const entry of entries) {
    const impact = appliedBalance(entry);
    if (impact !== 0) {
      const account = accounts.find((item) => item.id === entry.accountId);
      if (account) {
        const next: Account = {
          ...account,
          balance: { ...account.balance, amountMinor: account.balance.amountMinor - impact },
          updatedAt: isoNow(),
        };
        putCached("account", account.id, next, cachedVersion("account", account.id));
        enqueue({ entity: "account", action: "upsert", entityId: account.id, value: accountDTO(next), baseVersion: cachedVersion("account", account.id) });
        const index = accounts.indexOf(account);
        accounts[index] = next;
      }
    }
    deleteCached("transaction", entry.id);
    enqueue({ entity: "transaction", action: "delete", entityId: entry.id, value: null, baseVersion: cachedVersion("transaction", entry.id) });
  }
  notifyChanged();
}

// MARK: - Recurring bills

export function readRecurring(): RecurringPayment[] {
  return cachedRecurringPayments();
}

export function saveRecurringPayment(input: {
  id?: string;
  name: string;
  amountMinor: number;
  currency: string;
  frequency: TransactionFrequency;
  nextDate: Date;
  accountId?: string;
  category: string;
  isActive: boolean;
}) {
  const existing = input.id ? getCached<RecurringPayment>("recurringPayment", input.id) : null;
  const payment: RecurringPayment = {
    id: existing?.id ?? input.id ?? uuid(),
    name: input.name.trim(),
    amountMinor: input.amountMinor,
    currency: input.currency,
    frequency: input.frequency,
    nextDate: input.nextDate.toISOString(),
    accountId: input.accountId,
    category: input.category.trim() || "Bills",
    isActive: input.isActive,
    scheduleAnchorDay: existing?.scheduleAnchorDay,
  };
  const version = existing ? cachedVersion("recurringPayment", payment.id) : 0;
  putCached("recurringPayment", payment.id, payment, version);
  enqueue({ entity: "recurringPayment", action: "upsert", entityId: payment.id, value: recurringDTO(payment), baseVersion: version });
  notifyChanged();
  return payment;
}

export function deleteRecurringPayment(id: string) {
  const transactions = cachedTransactions().filter((transaction) => transaction.recurringPaymentId === id);
  for (const transaction of transactions) {
    if (transaction.source === "subscription" && transaction.pending) {
      deleteCached("transaction", transaction.id);
      enqueue({ entity: "transaction", action: "delete", entityId: transaction.id, value: null, baseVersion: cachedVersion("transaction", transaction.id) });
      continue;
    }
    updateTransaction(transaction.id, { recurringPaymentId: null });
  }
  deleteCached("recurringPayment", id);
  enqueue({ entity: "recurringPayment", action: "delete", entityId: id, value: null, baseVersion: cachedVersion("recurringPayment", id) });
  notifyChanged();
}

/** Simplified port of RecurringPaymentMatcher: same account, matching amount, within a few days. */
function linkNearbyBill(transaction: Transaction, payments: RecurringPayment[]) {
  if (transaction.recurringPaymentId) return;
  const amount = Math.abs(transaction.amount.amountMinor);
  if (amount === 0) return;
  const booked = new Date(transaction.bookedAt).getTime();
  const candidate = payments.find((payment) => {
    if (!payment.isActive || payment.accountId !== transaction.accountId) return false;
    if (payment.currency !== transaction.amount.currency) return false;
    if (Math.abs(payment.amountMinor - amount) > Math.max(100, payment.amountMinor * 0.02)) return false;
    const next = new Date(payment.nextDate).getTime();
    return Math.abs(next - booked) <= 1000 * 60 * 60 * 24 * 7;
  });
  if (!candidate) return;
  const next: Transaction = { ...transaction, recurringPaymentId: candidate.id };
  putCached("transaction", transaction.id, next, cachedVersion("transaction", transaction.id));
  enqueue({ entity: "transaction", action: "upsert", entityId: transaction.id, value: transactionDTO(next), baseVersion: cachedVersion("transaction", transaction.id) });
}
