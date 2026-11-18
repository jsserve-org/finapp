import { expect, test } from "bun:test";
import { currencyTotals, insights, parseMoney } from "./finance";

const accounts = [
  { id: "twd", name: "Cash", institution: "Manual", kind: "cash", balance: { amountMinor: 10000, currency: "TWD" }, updatedAt: "2026-11-01T00:00:00Z" },
  { id: "usd", name: "Bank", institution: "Manual", kind: "checking", balance: { amountMinor: 5000, currency: "USD" }, updatedAt: "2026-11-01T00:00:00Z" },
];
function transaction(id, minor, currency, month) {
  return { id, accountId: "twd", description: id, amount: { amountMinor: minor, currency }, bookedAt: new Date(2026, month - 1, 5, 12).toISOString(), pending: false, category: "Food", updatedAt: "2026-11-05T00:00:00Z" };
}

test("Insights keeps currencies separate and includes holdings in their own currency", () => {
  const result = insights(accounts, [transaction("in", 2500, "TWD", 11), transaction("out", -1000, "USD", 11)], [{ id: "stock", name: "Stock", symbol: "2330", quantity: 2, currentPriceMinor: 300, currency: "TWD" }], "2026-11");
  expect(currencyTotals(accounts)).toEqual([["TWD", 10000], ["USD", 5000]]);
  expect(result.totals).toEqual([{ currency: "TWD", balance: 10600, income: 2500, spending: 0 }, { currency: "USD", balance: 5000, income: 0, spending: 1000 }]);
  expect(result.portfolio).toEqual([["TWD", 600]]);
});

test("Category totals respect the chosen month and currency", () => {
  const result = insights([], [transaction("current", -100, "TWD", 11), transaction("previous", -200, "TWD", 10), transaction("dollars", -300, "USD", 11)], [], "2026-11");
  expect(result.categories).toEqual([{ category: "Food", currency: "USD", amount: 300 }, { category: "Food", currency: "TWD", amount: 100 }]);
  expect(result.months).toContain("2026-10");
});

test("Money inputs preserve cents and reject invalid or unsafe balances", () => {
  expect(parseMoney("0.29")).toBe(29);
  expect(parseMoney("-12.50")).toBe(-1250);
  expect(parseMoney(" 100 ")).toBe(10000);
  for (const text of ["", "NaN", "Infinity", "1e3", "1,2", "1.005", "99999999999999999"]) expect(parseMoney(text)).toBeNull();
});
