import type { Frame, Locator, Page } from "playwright";

export type MonthlyStatement = {
  source: "tcstock";
  capturedAt: string;
  statementMonth: string;
  tables: { headers: string[]; rows: string[][] }[];
};

function previousTaiwanMonth(): { year: string; month: string; label: string } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Taipei", year: "numeric", month: "2-digit",
  }).formatToParts(new Date());
  const year = Number(parts.find((part) => part.type === "year")?.value);
  const month = Number(parts.find((part) => part.type === "month")?.value);
  const previous = new Date(Date.UTC(year, month - 2, 1));
  const resultYear = String(previous.getUTCFullYear());
  const resultMonth = String(previous.getUTCMonth() + 1);
  return { year: resultYear, month: resultMonth, label: `${resultYear}-${resultMonth.padStart(2, "0")}` };
}

async function statementForm(page: Page): Promise<Frame> {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    const frame = page.frames().find((item) => {
      try { return new URL(item.url()).pathname === "/libs/eip/ebill.php"; }
      catch { return false; }
    });
    if (frame && await frame.locator("#search_button").isVisible().catch(() => false)) return frame;
    await new Promise((done) => setTimeout(done, 250));
  }
  throw new Error("TCStock monthly statement form did not load");
}

export async function fetchMonthlyStatement(
  page: Page,
  clickReadOnly: (target: Locator, goal: string) => Promise<void>,
): Promise<MonthlyStatement | null> {
  await clickReadOnly(page.frameLocator('frame[name="top"]').getByRole("link", { name: "帳務查詢" }), "Open account inquiry");
  await clickReadOnly(page.frameLocator('frame[name="_main"]').getByRole("link", { name: "對帳單", exact: true }), "Open the monthly statement query");
  const period = previousTaiwanMonth();
  let form = await statementForm(page);
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      await form.locator("#type").selectOption("2");
      await form.locator("#year").selectOption(period.year);
      await form.locator("#mon").selectOption(period.month);
      await form.locator("#search_button").click();
      break;
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes("Frame was detached") || attempt === 2) throw error;
      form = await statementForm(page);
    }
  }
  const result = form.getByRole("link", { name: period.label, exact: true });
  const found = await result.waitFor({ state: "visible", timeout: 10_000 }).then(() => true).catch(() => false);
  if (!found) {
    if (await form.getByText("查無資料").isVisible().catch(() => false)) return null;
    throw new Error(`TCStock did not return a monthly statement result for ${period.label}`);
  }
  await result.click();
  const deadline = Date.now() + 20_000;
  let statementPage: Page | undefined;
  while (Date.now() < deadline) {
    statementPage = page.context().pages().find((item) => {
      try {
        const url = new URL(item.url());
        return url.hostname.endsWith("tcstock.com.tw") && url.pathname === "/libs/eip/bill.php" &&
          url.searchParams.get("btdate")?.startsWith(period.label.replace("-", ""));
      } catch { return false; }
    });
    if (statementPage) break;
    await new Promise((done) => setTimeout(done, 250));
  }
  if (!statementPage) throw new Error(`TCStock did not open the ${period.label} statement`);
  await statementPage.locator("table th").first().waitFor({ state: "visible", timeout: 20_000 });
  const tables = await statementPage.locator("table").evaluateAll((elements) => elements.map((table) => ({
    headers: Array.from(table.querySelectorAll("th"), (cell) => cell.textContent?.replace(/\s+/g, " ").trim() ?? ""),
    rows: Array.from(table.querySelectorAll("tr"), (row) => Array.from(row.querySelectorAll("td"),
      (cell) => cell.textContent?.replace(/\s+/g, " ").trim() ?? ""))
      .filter((row) => row.length > 0 && row.some(Boolean)),
  })).filter((table) => table.headers.includes("交易日期")));
  if (tables.length === 0) throw new Error(`TCStock ${period.label} statement has no recognized trade table`);
  return { source: "tcstock", capturedAt: new Date().toISOString(), statementMonth: period.label, tables };
}
