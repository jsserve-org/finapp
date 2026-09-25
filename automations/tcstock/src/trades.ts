import type { Frame, Locator, Page } from "playwright";

export type TradeSnapshot = {
  source: "tcstock";
  capturedAt: string;
  period: { start: string; end: string };
  headers: string[];
  rows: string[][];
};

function lastThirtyDays(): { start: string; end: string } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Taipei", year: "numeric", month: "2-digit", day: "2-digit",
  }).formatToParts(new Date());
  const part = (type: string) => Number(parts.find((item) => item.type === type)?.value);
  const end = new Date(Date.UTC(part("year"), part("month") - 1, part("day")));
  const start = new Date(end.getTime() - 29 * 24 * 60 * 60 * 1000);
  const format = (date: Date) => date.toISOString().slice(0, 10);
  return { start: format(start), end: format(end) };
}

async function statementFrame(page: Page): Promise<Frame> {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    const frame = page.frames().find((item) => {
      try { return new URL(item.url()).pathname === "/libs/stock_search/stock_cmio.php"; }
      catch { return false; }
    });
    if (frame && await frame.locator("#s_date").isVisible().catch(() => false)) return frame;
    await new Promise((done) => setTimeout(done, 250));
  }
  throw new Error("TCStock securities statement frame did not load");
}

export async function fetchTrades(page: Page, clickReadOnly: (target: Locator, goal: string) => Promise<void>, startDate?: string): Promise<TradeSnapshot> {
  await clickReadOnly(page.frameLocator('frame[name="top"]').getByRole("link", { name: "帳務查詢" }), "Open account inquiry");
  await clickReadOnly(page.frameLocator('frame[name="_main"]').getByRole("link", { name: "證券對帳單" }), "Open the securities statement query");
  const frame = await statementFrame(page);
  const period = lastThirtyDays();
  if (startDate) {
    if (startDate > period.end) throw new Error("TCSTOCK_TRADES_START_DATE must not be after today");
    period.start = startDate;
  }
  await frame.locator("#s_date").fill(period.start);
  await frame.locator("#e_date").fill(period.end);
  await Promise.all([
    frame.waitForNavigation({ waitUntil: "domcontentloaded", timeout: 20_000 }),
    frame.locator('input[type="submit"]').click(),
  ]);
  await frame.locator("table th").first().waitFor({ state: "visible", timeout: 20_000 });
  const { headers, rows } = await frame.locator("table").first().evaluate((table) => ({
    headers: Array.from(table.querySelectorAll("th"), (cell) => cell.textContent?.replace(/\s+/g, " ").trim() ?? ""),
    rows: Array.from(table.querySelectorAll("tr"), (row) => Array.from(row.querySelectorAll("td"),
      (cell) => cell.textContent?.replace(/\s+/g, " ").trim() ?? ""))
      .filter((row) => row.length > 0 && row.some(Boolean)),
  }));
  if (!headers.includes("成交日期") || !headers.includes("成交數量")) {
    throw new Error("TCStock securities statement layout changed");
  }
  return { source: "tcstock", capturedAt: new Date().toISOString(), period, headers, rows };
}
