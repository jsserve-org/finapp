import type { Account, RecurringPayment, StockHolding, Transaction } from "./types";

export function netWorthByCurrency(accounts: Account[], holdings: StockHolding[]): { currency: string; amount: number }[] {
  const totals = new Map<string, number>();
  for (const account of accounts) {
    if (account.kind === "sharedCredit") continue;
    totals.set(account.balance.currency, (totals.get(account.balance.currency) ?? 0) + account.balance.amountMinor);
  }
  for (const holding of holdings) {
    totals.set(holding.currency, (totals.get(holding.currency) ?? 0) + Math.round(holding.quantity * holding.currentPriceMinor));
  }
  return [...totals.entries()].map(([currency, amount]) => ({ currency, amount })).sort((a, b) => a.currency.localeCompare(b.currency));
}

export function portfolioTotals(holdings: StockHolding[]): { currency: string; amount: number }[] {
  const totals = new Map<string, number>();
  for (const holding of holdings) {
    totals.set(holding.currency, (totals.get(holding.currency) ?? 0) + Math.round(holding.quantity * holding.currentPriceMinor));
  }
  return [...totals.entries()].map(([currency, amount]) => ({ currency, amount })).sort((a, b) => a.currency.localeCompare(b.currency));
}

export function flowsForCurrency(transactions: Transaction[], currency: string) {
  let inflow = 0;
  let outflow = 0;
  for (const transaction of transactions) {
    if (transaction.amount.currency !== currency) continue;
    if (transaction.amount.amountMinor > 0) inflow += transaction.amount.amountMinor;
    else outflow += Math.abs(transaction.amount.amountMinor);
  }
  return { inflow, outflow };
}

export function categoryTotals(
  transactions: Transaction[],
  month: Date,
): { category: string; currency: string; amount: number }[] {
  const totals = new Map<string, { category: string; currency: string; amount: number }>();
  for (const transaction of transactions) {
    if (transaction.amount.amountMinor >= 0) continue;
    const date = new Date(transaction.bookedAt);
    if (date.getFullYear() !== month.getFullYear() || date.getMonth() !== month.getMonth()) continue;
    const category = transaction.category ?? "Uncategorized";
    const key = `${transaction.amount.currency}|${category}`;
    const entry = totals.get(key) ?? { category, currency: transaction.amount.currency, amount: 0 };
    entry.amount += Math.abs(transaction.amount.amountMinor);
    totals.set(key, entry);
  }
  return [...totals.values()].sort((a, b) => b.amount - a.amount).slice(0, 8);
}

export function availableMonths(transactions: Transaction[]): Date[] {
  const months = new Map<string, Date>();
  for (const transaction of transactions) {
    const date = new Date(transaction.bookedAt);
    if (Number.isNaN(date.getTime())) continue;
    const month = new Date(date.getFullYear(), date.getMonth(), 1);
    months.set(`${date.getFullYear()}-${date.getMonth()}`, month);
  }
  const current = new Date();
  months.set(`${current.getFullYear()}-${current.getMonth()}`, new Date(current.getFullYear(), current.getMonth(), 1));
  return [...months.values()].sort((a, b) => b.getTime() - a.getTime());
}

export function transactionPresentation(transaction: Transaction) {
  const awaitingSettlement =
    transaction.pending === true &&
    transaction.amount.amountMinor === 0 &&
    transaction.originalAmount != null;
  const amountMinor = awaitingSettlement ? (transaction.originalAmount?.amountMinor ?? 0) : transaction.amount.amountMinor;
  const currency = awaitingSettlement ? (transaction.originalAmount?.currency ?? transaction.amount.currency) : transaction.amount.currency;
  return { amountMinor, currency, awaitingSettlement };
}

export function isIncludedInNetWorth(account: Account) {
  return account.kind !== "sharedCredit";
}

export function pendingBills(payments: RecurringPayment[]) {
  return payments.filter((payment) => payment.isActive);
}
