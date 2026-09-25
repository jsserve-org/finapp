import { spawn } from "node:child_process";

const bun = Bun.which("bun");
if (!bun) throw new Error("bun is not on PATH");
const needVirtualDisplay = process.platform === "linux" && !process.env.DISPLAY && process.env.TCSTOCK_HEADLESS !== "true";
const xvfb = needVirtualDisplay ? Bun.which("xvfb-run") : null;
if (needVirtualDisplay && !xvfb) {
  throw new Error("ACTION_REQUIRED: Headed TCStock cron needs xvfb-run on a Linux server without DISPLAY");
}
const command = xvfb ?? bun;
const args = xvfb ? ["-a", bun, "run", "start"] : ["run", "start"];
const child = spawn(command, args, { stdio: "inherit", env: process.env });
for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => child.kill(signal));
const code = await new Promise<number>((done, reject) => {
  child.once("error", reject);
  child.once("close", (status) => done(status ?? 1));
});
process.exitCode = code;
