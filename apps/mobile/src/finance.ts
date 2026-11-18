import type { Account, Transaction } from "@ledgerly/contracts";

export type Holding = { id: string; symbol: string; name: string; quantity: number; currentPriceMinor: number; currency: string };
export const monthKey = (date: Date) => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
export const monthLabel = (month: string) => new Date(`${month}-01T12:00:00`).toLocaleDateString(undefined, { month: "short", year: "numeric" });

export function currencyTotals(accounts: Account[]) {
  const totals = new Map<string, number>();
  for (const account of accounts) totals.set(account.balance.currency, (totals.get(account.balance.currency) ?? 0) + account.balance.amountMinor);
  return [...totals].sort(([a], [b]) => a.localeCompare(b));
}

export function insights(accounts: Account[], transactions: Transaction[], holdings: Holding[], month: string) {
  const totals = new Map(currencyTotals(accounts).map(([currency, balance]) => [currency, { currency, balance, income: 0, spending: 0 }]));
  const categories = new Map<string, { category: string; currency: string; amount: number }>();
  const portfolio = new Map<string, number>();
  for (const holding of holdings) {
    const value = Math.round(holding.quantity * holding.currentPriceMinor);
    portfolio.set(holding.currency, (portfolio.get(holding.currency) ?? 0) + value);
    const total = totals.get(holding.currency) ?? { currency: holding.currency, balance: 0, income: 0, spending: 0 };
    total.balance += value;
    totals.set(holding.currency, total);
  }
  for (const transaction of transactions) {
    const { currency, amountMinor } = transaction.amount;
    const total = totals.get(currency) ?? { currency, balance: 0, income: 0, spending: 0 };
    if (amountMinor > 0) total.income += amountMinor;
    else total.spending -= amountMinor;
    totals.set(currency, total);
    const date = new Date(transaction.bookedAt);
    if (amountMinor < 0 && Number.isFinite(date.getTime()) && monthKey(date) === month) {
      const category = transaction.category ?? "Uncategorized";
      const key = JSON.stringify([currency, category]);
      const item = categories.get(key) ?? { category, currency, amount: 0 };
      item.amount -= amountMinor;
      categories.set(key, item);
    }
  }
  const months = [...new Set([monthKey(new Date()), ...transactions.filter(t => Number.isFinite(Date.parse(t.bookedAt))).map(t => monthKey(new Date(t.bookedAt)))])].sort().reverse();
  return { totals: [...totals.values()].sort((a, b) => a.currency.localeCompare(b.currency)), categories: [...categories.values()].sort((a, b) => b.amount - a.amount).slice(0, 8), portfolio: [...portfolio].sort(([a], [b]) => a.localeCompare(b)), months };
}

/** Decimal money input, without floating point rounding or silently accepting invalid text. */
export function parseMoney(text: string): number | null {
  const match = /^(-?)(\d+)(?:\.(\d{0,2}))?$/.exec(text.trim());
  if (!match) return null;
  const minor = (Number(match[2]) * 100 + Number((match[3] ?? "").padEnd(2, "0"))) * (match[1] ? -1 : 1);
  return Number.isSafeInteger(minor) ? minor : null;
}
