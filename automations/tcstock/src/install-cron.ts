import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { z } from "zod";

const schedule = z.string().regex(/^[\d*/,-]+(?:\s+[\d*/,-]+){4}$/).parse(process.env.STOCK_CRON);
const cwd = resolve(import.meta.dir, "..");
const bun = Bun.which("bun");
if (!bun) throw new Error("bun is not on PATH");
const quote = (value: string) => `'${value.replaceAll("'", `'\\''`)}'`;
const marker = "# ledgerly-tcstock";
const entry = `${schedule} umask 077 && cd ${quote(cwd)} && ${quote(bun)} run cron:run >> ${quote(resolve(cwd, "cron.log"))} 2>&1 ${marker}`;
const current = spawnSync("crontab", ["-l"], { encoding: "utf8" });
if (current.error) throw current.error;
const existing = current.status === 0 ? current.stdout : "";
const lines = existing.split("\n").filter((line) => line.trim() && !line.endsWith(marker));
const result = spawnSync("crontab", ["-"], { input: [...lines, entry, ""].join("\n"), encoding: "utf8" });
if (result.status !== 0) throw new Error(result.stderr || "Could not install crontab entry");
console.log(`Installed TCStock cron schedule: ${schedule}`);
