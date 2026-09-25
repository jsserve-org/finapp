import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { z } from "zod";

const schedule = z.string().regex(/^[\d*/,-]+(?:\s+[\d*/,-]+){4}$/).parse(process.env.STOCK_CRON);
const cwd = resolve(import.meta.dir, "..");
const docker = Bun.which("docker");
if (!docker) throw new Error("docker is not on PATH");
const quote = (value: string) => `'${value.replaceAll("'", `'\\''`)}'`;
const marker = "# ledgerly-tcstock-remote";
const entry = `${schedule} cd ${quote(cwd)} && ${quote(docker)} compose -f ${quote(resolve(cwd, "compose.yml"))} exec -T runner bun run src/trigger-remote.ts >> ${quote(resolve(cwd, "cron.log"))} 2>&1 ${marker}`;
const current = spawnSync("crontab", ["-l"], { encoding: "utf8" });
if (current.error) throw current.error;
if (current.status !== 0 && !/no crontab/i.test(current.stderr)) {
  throw new Error(current.stderr || "Could not read crontab");
}
const existing = current.status === 0 ? current.stdout : "";
const lines = existing.split("\n").filter((line) => line.trim() && !line.endsWith(marker));
const result = spawnSync("crontab", ["-"], { input: [...lines, entry, ""].join("\n"), encoding: "utf8" });
if (result.status !== 0) throw new Error(result.stderr || "Could not install crontab entry");
console.log(`Installed TCStock remote cron schedule: ${schedule}`);
