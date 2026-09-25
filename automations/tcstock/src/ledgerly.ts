import { createHash } from "node:crypto";
import { z } from "zod";
import type { TradeSnapshot } from "./trades";

const changeSchema = z.object({ entity: z.string(), entityId: z.string(), action: z.string(), value: z.unknown() });
const syncSchema = z.object({ cursor: z.string(), changes: z.array(changeSchema), acceptedMutationIds: z.array(z.string()) });

type StockTrade = {
  id: string;
  holdingId: string;
  symbol: string;
  side: "buy" | "sell";
  quantity: number;
  priceMinor: number;
  feesMinor: number;
  currency: "TWD";
  tradedAt: string;
  linkedAccountId: null;
};

type StockHolding = {
  id: string;
  symbol: string;
  name: string;
  quantity: number;
  averageCostMinor: number;
  currentPriceMinor: number;
  currency: "TWD";
  linkedAccountId: null;
  updatedAt: string;
};

type TradeOperation = {
  mutationId: string;
  entity: "stockTrade";
  action: "upsert";
  entityId: string;
  value: StockTrade;
  baseVersion: 0;
};

type HoldingOperation = {
  mutationId: string;
  entity: "stockHolding";
  action: "upsert";
  entityId: string;
  value: StockHolding;
  baseVersion: 0;
};

type Operation = TradeOperation | HoldingOperation;

const stockTradeSchema = z.object({
  id: z.string(), holdingId: z.string(), symbol: z.string(), side: z.enum(["buy", "sell"]),
  quantity: z.number().positive(), priceMinor: z.number().int().positive(), feesMinor: z.number().int().nonnegative(),
  currency: z.literal("TWD"), tradedAt: z.string(), linkedAccountId: z.null(),
});

function stableId(value: string): string {
  const hex = createHash("sha256").update(value).digest("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-5${hex.slice(13, 16)}-a${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

function numberFromCell(value: string): number {
  const clean = value.replaceAll(",", "").trim();
  if (!/^\d+(?:\.\d+)?$/.test(clean)) throw new Error("TCStock trade contains an unsupported number format");
  const result = Number(clean);
  if (!Number.isFinite(result)) throw new Error("TCStock trade contains a non-finite number");
  return result;
}

function minorFromCell(value: string): number {
  const minor = Math.round(numberFromCell(value) * 100);
  if (!Number.isSafeInteger(minor)) throw new Error("TCStock amount exceeds the supported range");
  return minor;
}

export function tradeOperations(snapshot: TradeSnapshot): TradeOperation[] {
  const column = (name: string): number => {
    const index = snapshot.headers.indexOf(name);
    if (index < 0) throw new Error(`TCStock trade column ${name} is missing`);
    return index;
  };
  const date = column("成交日期");
  const product = column("商品");
  const kind = column("交易類別");
  const side = column("買賣別");
  const quantity = column("成交數量");
  const price = column("成交價格");
  const fee = column("手續費");
  const tax = column("交易稅");
  const occurrences = new Map<string, number>();

  return snapshot.rows.map((row) => {
    if (row.length !== snapshot.headers.length || row[kind] !== "現股") {
      throw new Error("TCStock trade contains an unsupported row or trade type");
    }
    const symbol = /^\(([^)]+)\)/.exec(row[product])?.[1];
    if (!symbol || !/^[0-9A-Za-z]+$/.test(symbol)) throw new Error("TCStock trade symbol could not be parsed");
    const direction = row[side] === "買進" ? "buy" : row[side] === "賣出" ? "sell" : null;
    if (!direction) throw new Error("TCStock trade side could not be parsed");
    if (!/^\d{4}-\d{2}-\d{2}$/.test(row[date]) || !Number.isFinite(Date.parse(row[date]))) {
      throw new Error("TCStock trade date could not be parsed");
    }
    const count = numberFromCell(row[quantity]);
    if (count <= 0) throw new Error("TCStock trade quantity must be positive");
    const signature = JSON.stringify(row);
    const occurrence = occurrences.get(signature) ?? 0;
    occurrences.set(signature, occurrence + 1);
    const id = stableId(`tcstock-trade|${signature}|${occurrence}`);
    const value: StockTrade = {
      id,
      holdingId: stableId(`tcstock-symbol|${symbol}|TWD`),
      symbol,
      side: direction,
      quantity: count,
      priceMinor: minorFromCell(row[price]),
      feesMinor: minorFromCell(row[fee]) + minorFromCell(row[tax]),
      currency: "TWD",
      tradedAt: `${row[date]}T12:00:00.000+08:00`,
      linkedAccountId: null,
    };
    return { mutationId: stableId(`tcstock-import|${id}`), entity: "stockTrade", action: "upsert", entityId: id, value, baseVersion: 0 };
  });
}

export function holdingOperations(trades: StockTrade[], updatedAt: string): HoldingOperation[] {
  const grouped = new Map<string, StockTrade[]>();
  for (const trade of trades) {
    const group = grouped.get(trade.holdingId) ?? [];
    group.push(trade);
    grouped.set(trade.holdingId, group);
  }
  return [...grouped.entries()].map(([holdingId, unsorted]) => {
    const ordered = [...unsorted].sort((left, right) => left.tradedAt.localeCompare(right.tradedAt) || left.id.localeCompare(right.id));
    let quantity = 0;
    let averageCostMinor = 0;
    let currentPriceMinor = 0;
    for (const trade of ordered) {
      currentPriceMinor = trade.priceMinor;
      if (trade.side === "buy") {
        const nextQuantity = quantity + trade.quantity;
        averageCostMinor = Math.round((quantity * averageCostMinor + trade.quantity * trade.priceMinor + trade.feesMinor) / nextQuantity);
        quantity = nextQuantity;
      } else {
        if (trade.quantity > quantity) throw new Error(`TCStock needs a full trade-history backfill before it can calculate ${trade.symbol}`);
        quantity -= trade.quantity;
        if (quantity === 0) averageCostMinor = 0;
      }
    }
    const latest = ordered.at(-1);
    if (!latest) throw new Error("TCStock holding has no trades");
    const value: StockHolding = {
      id: holdingId, symbol: latest.symbol, name: latest.symbol, quantity,
      averageCostMinor, currentPriceMinor, currency: "TWD", linkedAccountId: null, updatedAt,
    };
    return {
      mutationId: stableId(`tcstock-holding-import|${holdingId}|${JSON.stringify(value)}`),
      entity: "stockHolding", action: "upsert", entityId: holdingId, value, baseVersion: 0,
    };
  });
}

export class LedgerlyImporter {
  constructor(private readonly baseUrl: string, private readonly apiKey: string) {}

  private async exchange(cursor: string, operations: Operation[]) {
    const response = await fetch(new URL("/v1/sync", this.baseUrl), {
      method: "POST",
      headers: { authorization: `Bearer ${this.apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({ protocolVersion: 2, cursor, operations }),
    });
    if (!response.ok) throw new Error(`Ledgerly sync failed with HTTP ${response.status}`);
    return syncSchema.parse(await response.json());
  }

  async import(snapshot: TradeSnapshot): Promise<{ imported: number; existing: number }> {
    const existing = new Map<string, StockTrade>();
    let cursor = "0";
    while (true) {
      const result = await this.exchange(cursor, []);
      for (const change of result.changes) {
        if (change.entity !== "stockTrade") continue;
        if (change.action === "delete") existing.delete(change.entityId);
        else existing.set(change.entityId, stockTradeSchema.parse(change.value));
      }
      if (result.cursor === cursor || result.changes.length < 500) break;
      cursor = result.cursor;
    }
    const newTrades = tradeOperations(snapshot).filter((operation) => !existing.has(operation.entityId));
    for (const operation of newTrades) existing.set(operation.entityId, operation.value);
    const operations: Operation[] = [...newTrades, ...holdingOperations([...existing.values()], snapshot.capturedAt)];
    for (let offset = 0; offset < operations.length; offset += 100) {
      const batch = operations.slice(offset, offset + 100);
      const result = await this.exchange("0", batch);
      if (batch.some((operation) => !result.acceptedMutationIds.includes(operation.mutationId))) {
        throw new Error("Ledgerly rejected one or more TCStock trades");
      }
    }
    return { imported: newTrades.length, existing: snapshot.rows.length - newTrades.length };
  }
}
