import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { chromium, type BrowserContext, type Frame, type Locator, type Page } from "playwright";
import { z } from "zod";
import { chooseNavigation, readImageCode, type Candidate } from "./models";
import { fetchTrades } from "./trades";
import { fetchMonthlyStatement } from "./statements";
import { LedgerlyImporter } from "./ledgerly";

const config = z.object({
  TYPESAFE_API_KEY: z.string().optional(),
  TYPESAFE_MODEL: z.string().default("jev-latest"),
  TCSTOCK_IDNO: z.string().optional(),
  TCSTOCK_PASSWORD: z.string().optional(),
  TCSTOCK_AUTO_LOGIN: z.enum(["true", "false"]).default("false"),
  OPENROUTER_API_KEY: z.string().optional(),
  OPENROUTER_CAPTCHA_MODEL: z.string().default("openai/gpt-6-luna"),
  TCSTOCK_HEADLESS: z.enum(["true", "false"]).default("false"),
  TCSTOCK_BROWSER_CHANNEL: z.enum(["chrome", "chromium"]).default("chrome"),
  TCSTOCK_CDP_URL: z.string().url().optional(),
  TCSTOCK_OUTPUT_DIR: z.string().default("./output"),
  TCSTOCK_PROFILE_DIR: z.string().default("./profile"),
  TCSTOCK_LOGIN_TIMEOUT_MS: z.coerce.number().int().positive().default(180_000),
  TCSTOCK_TRADES_START_DATE: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  LEDGERLY_API_URL: z.string().url().optional(),
  LEDGERLY_API_KEY: z.string().min(1).optional(),
  TCSTOCK_IMAGE_CODE_SELECTOR: z.string().optional(),
  TCSTOCK_IMAGE_INPUT_SELECTOR: z.string().optional(),
  TCSTOCK_DEBUG_CDP_PORT: z.coerce.number().int().min(1024).max(65535).optional(),
}).parse(process.env);

const LOGIN_URL = "https://www.tcstock.com.tw/TCS/auth/index.php";
const PORTAL_URL = "https://www.tcstock.com.tw/TCS/";
const SAFE = /證券|股票|帳務|查詢|對帳單|statement|account|inquiry/iu;
const FORBIDDEN = /買|賣|下單|委託|轉帳|匯款|申購|贖回|設定|修改|刪除|登出|trade|order|buy|sell|transfer|settings|delete|logout/iu;

type NavigationCandidate = Candidate & { frame: Frame };

function isBrokerageUrl(url: string): boolean {
  try {
    const host = new URL(url).hostname;
    return host === "tcstock.com.tw" || host.endsWith(".tcstock.com.tw");
  }
  catch { return false; }
}

async function hasTrustedSession(page: Page, timeout = 0): Promise<boolean> {
  const deadline = Date.now() + timeout;
  do {
    const top = page.frame({ name: "top" });
    const main = page.frame({ name: "_main" });
    const signedIn = await top?.locator('a[href*="func=exit"]').isVisible().catch(() => false) ?? false;
    const mainText = await main?.locator("body").innerText().catch(() => "") ?? "";
    if (/頁面過期|請重新登入/.test(mainText)) return false;
    if (signedIn && mainText.trim().length > 0) return true;
    if (timeout === 0) return false;
    await new Promise((done) => setTimeout(done, 250));
  } while (Date.now() < deadline);
  return false;
}

async function waitForTrustedSession(context: BrowserContext): Promise<Page> {
  const deadline = Date.now() + config.TCSTOCK_LOGIN_TIMEOUT_MS;
  while (Date.now() < deadline) {
    for (const page of context.pages().filter((item) => isBrokerageUrl(item.url())).reverse()) {
      if (!page.isClosed() && await hasTrustedSession(page)) return page;
    }
    await new Promise((done) => setTimeout(done, 500));
  }
  throw new Error("ACTION_REQUIRED: TCStock sign-in or mobile verification did not complete before the timeout");
}

async function waitForGate(page: Page): Promise<void> {
  await page.waitForFunction(() => document.title !== "reCAPTCHA 驗證頁面" ||
    document.body.innerText.includes("請完成圖片驗證"), undefined, { timeout: 30_000 }).catch(() => undefined);
  if (!(await page.title()).includes("reCAPTCHA 驗證頁面")) return;
  if (config.TCSTOCK_HEADLESS === "true") {
    throw new Error("ACTION_REQUIRED: TCStock requested interactive reCAPTCHA; use a headed Chrome session");
  }
  console.log("Complete TCStock's reCAPTCHA in Chrome. Waiting for the login page...");
  await page.locator("#pass").waitFor({ state: "visible", timeout: config.TCSTOCK_LOGIN_TIMEOUT_MS })
    .catch(() => { throw new Error("ACTION_REQUIRED: TCStock reCAPTCHA was not completed before the timeout"); });
}

async function maybeReadImageCode(page: Page): Promise<void> {
  const imageSelector = config.TCSTOCK_IMAGE_CODE_SELECTOR;
  const inputSelector = config.TCSTOCK_IMAGE_INPUT_SELECTOR;
  if (!imageSelector || !inputSelector) return;
  if (!config.OPENROUTER_API_KEY) throw new Error("OPENROUTER_API_KEY is needed for a separate login image code");
  const image = page.locator(imageSelector);
  if (!await image.isVisible().catch(() => false)) return;
  const code = await readImageCode(await image.screenshot(), config.OPENROUTER_API_KEY, config.OPENROUTER_CAPTCHA_MODEL);
  await page.locator(inputSelector).fill(code);
}

async function signIn(context: BrowserContext, page: Page): Promise<Page> {
  if (!new URL(page.url()).pathname.startsWith("/TCS/auth/")) {
    await page.goto(LOGIN_URL, { waitUntil: "domcontentloaded", timeout: 30_000 });
  }
  await waitForGate(page);
  if (await page.locator("#pass").isVisible().catch(() => false)) {
    if (config.TCSTOCK_IDNO && config.TCSTOCK_PASSWORD) {
      await page.locator("#idno").fill(config.TCSTOCK_IDNO);
      await page.locator("#pass").fill(config.TCSTOCK_PASSWORD);
      await maybeReadImageCode(page);
      await page.locator("#svg_button").click();
    } else {
      if (config.TCSTOCK_HEADLESS === "true") {
        throw new Error("ACTION_REQUIRED: TCSTOCK_IDNO and TCSTOCK_PASSWORD are needed for unattended sign-in");
      }
      console.log("Sign in to TCStock in Chrome, including mobile verification if requested...");
      await maybeReadImageCode(page);
    }
  }
  return waitForTrustedSession(context);
}

async function tryRemoteSignIn(context: BrowserContext, page: Page): Promise<Page> {
  if (config.TCSTOCK_AUTO_LOGIN !== "true" || !config.TCSTOCK_IDNO || !config.TCSTOCK_PASSWORD) {
    throw new Error("ACTION_REQUIRED: Sign in and complete verification in the remote browser, then run sync again");
  }
  if (!new URL(page.url()).pathname.startsWith("/TCS/auth/") ||
      !await page.locator("#pass").isVisible().catch(() => false)) {
    throw new Error("ACTION_REQUIRED: Open the TCStock login form in the remote browser, then run sync again");
  }
  await page.locator("#idno").fill(config.TCSTOCK_IDNO);
  await page.locator("#pass").fill(config.TCSTOCK_PASSWORD);
  await maybeReadImageCode(page);
  await page.locator("#svg_button").click({ timeout: 5_000 }).catch(() => {
    throw new Error("ACTION_REQUIRED: Complete the visible TCStock challenge in the remote browser");
  });
  return waitForTrustedSession(context);
}

function scrub(label: string): string {
  return label.replace(/\d+/g, "[number]").replace(/\s+/g, " ").trim().slice(0, 90);
}

async function getCandidates(page: Page): Promise<NavigationCandidate[]> {
  const found: NavigationCandidate[] = [];
  for (const [index, frame] of page.frames().entries()) {
    if (!isBrokerageUrl(frame.url())) continue;
    const raw = await frame.locator("a, button, [role='button'], [role='menuitem']").evaluateAll((elements, prefix) => {
      const candidates: Candidate[] = [];
      for (const element of elements) {
        const html = element as HTMLElement;
        const bounds = html.getBoundingClientRect();
        if (!bounds.width || !bounds.height) continue;
        const label = (html.innerText || html.getAttribute("aria-label") || html.getAttribute("title") || "").trim();
        if (!label || label.length > 90) continue;
        const id = `tcstock-option-${prefix}-${candidates.length}`;
        html.setAttribute("data-tcstock-option", id);
        candidates.push({ id, label });
      }
      return candidates;
    }, index).catch(() => []);
    found.push(...raw.map(({ id, label }) => ({ id, label: scrub(label), frame }))
      .filter(({ label }) => SAFE.test(label) && !FORBIDDEN.test(label)));
  }
  return found.slice(0, 40);
}

async function clickReadOnly(page: Page, target: Locator, goal: string): Promise<void> {
  try {
    await target.click({ timeout: 6_000 });
    return;
  } catch (error) {
    if (!config.TYPESAFE_API_KEY) throw new Error(`Playwright could not ${goal}; configure TYPESAFE_API_KEY for Jev fallback`, { cause: error });
  }
  const candidates = await getCandidates(page);
  const selected = await chooseNavigation(candidates.map(({ id, label }) => ({ id, label })),
    config.TYPESAFE_API_KEY, config.TYPESAFE_MODEL, goal);
  const option = candidates.find(({ id }) => id === selected);
  if (!option) throw new Error(`Jev could not safely ${goal}`);
  await option.frame.locator(`[data-tcstock-option="${option.id}"]`).click({ timeout: 10_000 });
}

async function writePrivateJson(destination: string, value: unknown): Promise<void> {
  const temporary = `${destination}.${crypto.randomUUID()}.tmp`;
  try {
    await writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600, flag: "wx" });
    await rename(temporary, destination);
  } finally {
    await rm(temporary, { force: true });
  }
}

async function main(): Promise<void> {
  const outputDir = resolve(config.TCSTOCK_OUTPUT_DIR);
  const profileDir = resolve(config.TCSTOCK_PROFILE_DIR);
  await mkdir(outputDir, { recursive: true, mode: 0o700 });
  await mkdir(profileDir, { recursive: true, mode: 0o700 });
  const remote = config.TCSTOCK_CDP_URL ? await chromium.connectOverCDP(config.TCSTOCK_CDP_URL) : null;
  const context = remote?.contexts()[0] ?? await chromium.launchPersistentContext(profileDir, {
    channel: config.TCSTOCK_BROWSER_CHANNEL, headless: config.TCSTOCK_HEADLESS === "true", locale: "zh-TW",
    args: config.TCSTOCK_DEBUG_CDP_PORT ? [`--remote-debugging-port=${config.TCSTOCK_DEBUG_CDP_PORT}`] : [],
  });
  try {
    let page: Page | undefined;
    for (const candidate of context.pages().filter((item) => isBrokerageUrl(item.url())).reverse()) {
      if (await hasTrustedSession(candidate)) { page = candidate; break; }
    }
    page ??= context.pages().find((item) => {
      try { return isBrokerageUrl(item.url()) && new URL(item.url()).pathname.startsWith("/TCS/auth/"); }
      catch { return false; }
    }) ?? context.pages().find((item) => item.url() === PORTAL_URL) ??
      context.pages().find((item) => isBrokerageUrl(item.url())) ?? await context.newPage();
    if (!isBrokerageUrl(page.url())) await page.goto(PORTAL_URL, { waitUntil: "domcontentloaded", timeout: 30_000 });
    if (!await hasTrustedSession(page, 10_000)) {
      if (remote) {
        page = await tryRemoteSignIn(context, page);
      } else {
        page = await signIn(context, page);
      }
    }
    const trades = await fetchTrades(page, (target, goal) => clickReadOnly(page, target, goal), config.TCSTOCK_TRADES_START_DATE);
    const destination = resolve(outputDir, config.TCSTOCK_TRADES_START_DATE
      ? `trades-${trades.period.start}-to-${trades.period.end}.json`
      : `trades-${trades.period.end}.json`);
    await writePrivateJson(destination, trades);
    console.log(`Saved ${trades.rows.length} securities trade row(s) to ${destination}`);
    if (config.LEDGERLY_API_URL || config.LEDGERLY_API_KEY) {
      if (!config.LEDGERLY_API_URL || !config.LEDGERLY_API_KEY) {
        throw new Error("Ledgerly sync needs both LEDGERLY_API_URL and LEDGERLY_API_KEY");
      }
      const imported = await new LedgerlyImporter(config.LEDGERLY_API_URL, config.LEDGERLY_API_KEY).import(trades);
      console.log(`Ledgerly synced ${imported.imported} new stock trade(s); ${imported.existing} already present`);
    }
    const statement = await fetchMonthlyStatement(page, (target, goal) => clickReadOnly(page, target, goal));
    if (statement) {
      const statementPath = resolve(outputDir, `statement-${statement.statementMonth}.json`);
      await writePrivateJson(statementPath, statement);
      console.log(`Saved ${statement.tables.length} monthly statement table(s) to ${statementPath}`);
    } else {
      console.log("No securities monthly statement is available for the previous month yet");
    }
  } finally {
    if (config.TCSTOCK_DEBUG_CDP_PORT && !remote) {
      console.log("Debug Chrome is staying open. Press Enter in this terminal to close it.");
      await new Promise<void>((done) => process.stdin.once("data", () => done()));
    }
    if (remote) await remote.close();
    else await context.close();
  }
}

await main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
