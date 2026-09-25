import { describe, expect, test } from "bun:test";
import { holdingOperations, tradeOperations } from "./ledgerly";
import type { TradeSnapshot } from "./trades";

const snapshot: TradeSnapshot = {
  source: "tcstock",
  capturedAt: "2026-09-25T00:00:00.000Z",
  period: { start: "2026-04-01", end: "2026-09-25" },
  headers: ["成交日期", "委託書號", "商品", "交易類別", "買賣別", "成交數量", "成交價格", "手續費", "交易稅"],
  rows: [["2026-04-02", "12345-0001", "(2330)測試公司", "現股", "賣出", "1,000", "42.50", "20", "127"]],
};

describe("TCStock trade import", () => {
  test("maps a trade to stable Ledgerly units and IDs", () => {
    const first = tradeOperations(snapshot)[0];
    const again = tradeOperations(snapshot)[0];
    expect(first).toEqual(again);
    expect(first.value).toMatchObject({
      symbol: "2330", side: "sell", quantity: 1000,
      priceMinor: 4250, feesMinor: 14700, currency: "TWD",
      tradedAt: "2026-04-02T12:00:00.000+08:00", linkedAccountId: null,
    });
  });

  test("keeps identical fills distinct and rejects unsupported trade types", () => {
    const repeated = tradeOperations({ ...snapshot, rows: [snapshot.rows[0], snapshot.rows[0]] });
    expect(new Set(repeated.map((item) => item.entityId)).size).toBe(2);
    const unsupported = [...snapshot.rows[0]];
    unsupported[3] = "融資";
    expect(() => tradeOperations({ ...snapshot, rows: [unsupported] })).toThrow();
  });

  test("derives a synced holding from imported trade history", () => {
    const buySnapshot = { ...snapshot, rows: [
      ["2026-04-01", "12345-0000", "(2330)測試公司", "現股", "買進", "2,000", "40.00", "20", "0"],
      snapshot.rows[0],
    ] };
    const trades = tradeOperations(buySnapshot).map((operation) => operation.value);
    const holding = holdingOperations(trades, snapshot.capturedAt)[0];
    expect(holding.value).toMatchObject({ symbol: "2330", quantity: 1000, averageCostMinor: 4001, currentPriceMinor: 4250, currency: "TWD" });
  });
});
