import { spawn } from "node:child_process";
import { createWriteStream } from "node:fs";
import { mkdir } from "node:fs/promises";
import { resolve } from "node:path";

const cwd = resolve(import.meta.dir, "..");
const outputDir = resolve(process.env.TCSTOCK_OUTPUT_DIR || resolve(cwd, "output"));
await mkdir(outputDir, { recursive: true, mode: 0o700 });
const bun = Bun.which("bun");
if (!bun) throw new Error("bun is not on PATH");
const localBrowser = process.env.TCSTOCK_LOCAL_BROWSER === "true";
const csrf = crypto.randomUUID();
let running = false;
let startedAt: string | null = null;
let finishedAt: string | null = null;
let lastExitCode: number | null = null;

function startRun(): boolean {
  if (running) return false;
  running = true;
  startedAt = new Date().toISOString();
  finishedAt = null;
  lastExitCode = null;
  const log = createWriteStream(resolve(outputDir, "runner.log"), { flags: "a", mode: 0o600 });
  log.write(`\n[${startedAt}] Starting TCStock sync\n`);
  const child = spawn(bun!, ["run", "start"], {
    cwd,
    env: {
      ...process.env,
      TCSTOCK_CDP_URL: "http://127.0.0.1:9223",
      TCSTOCK_BROWSER_CHANNEL: "chromium",
      TCSTOCK_HEADLESS: "false",
    },
    stdio: "pipe",
  });
  child.stdin.end();
  child.stdout?.pipe(log, { end: false });
  child.stderr?.pipe(log, { end: false });
  child.once("error", (error) => log.write(`Runner failed to start: ${error.message}\n`));
  child.once("close", (code) => {
    lastExitCode = code ?? 1;
    finishedAt = new Date().toISOString();
    running = false;
    log.end(`[${finishedAt}] Finished with exit code ${lastExitCode}\n`);
  });
  return true;
}

const browserPanel = localBrowser
  ? `<main><p>Use the separate TCStock Chrome window on this laptop to sign in and complete verification.</p><p>Once the account page opens there, return here and click <strong>Run sync now</strong>.</p></main>`
  : `<iframe title="TCStock browser" src="/browser/vnc.html?autoconnect=true&resize=scale&path=browser/websockify"></iframe>`;

const page = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TCStock runner</title><style>
body{font:16px system-ui,sans-serif;margin:0;background:#101827;color:#edf2fa}
header{display:flex;align-items:center;gap:1rem;padding:1rem 1.25rem;background:#1b2940}
h1{font-size:1.2rem;margin:0;flex:1}button{background:#73b5ff;color:#08182c;border:0;border-radius:.5rem;padding:.7rem 1rem;font:inherit;font-weight:700;cursor:pointer}
button:disabled{opacity:.5;cursor:default}#status{padding:.65rem 1.25rem;color:#cbd7e7}
iframe{display:block;width:100%;height:calc(100dvh - 115px);border:0;background:#fff}
main{max-width:48rem;padding:1.25rem;line-height:1.6}
</style></head><body><header><h1>TCStock runner</h1><button id="run">Run sync now</button></header>
<div id="status" role="status">Checking runner…</div>
${browserPanel}
<script>
const csrf=${JSON.stringify(csrf)};
const status=document.getElementById('status');const run=document.getElementById('run');
async function refresh(){try{const r=await fetch('/api/status',{cache:'no-store'});const x=await r.json();run.disabled=x.running;
status.textContent=x.running?'Sync running since '+x.startedAt:x.finishedAt?'Last sync '+(x.lastExitCode===0?'succeeded':'needs attention')+' at '+x.finishedAt:'No sync run yet';}
catch{status.textContent='Runner status unavailable';}}
run.onclick=async()=>{run.disabled=true;const r=await fetch('/api/run',{method:'POST',headers:{'X-CSRF-Token':csrf}});
if(!r.ok)status.textContent='Could not start sync';await refresh();};refresh();setInterval(refresh,5000);
</script></body></html>`;

Bun.serve({
  hostname: "127.0.0.1",
  port: Number(process.env.TCSTOCK_CONTROL_PORT || 8081),
  async fetch(request) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/") {
      return new Response(page, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" } });
    }
    if (request.method === "GET" && url.pathname === "/api/status") {
      return Response.json({ running, startedAt, finishedAt, lastExitCode }, { headers: { "cache-control": "no-store" } });
    }
    if (request.method === "POST" && url.pathname === "/api/run") {
      if (request.headers.get("x-csrf-token") !== csrf) return new Response("Forbidden", { status: 403 });
      const started = startRun();
      return Response.json({ started }, { status: started ? 202 : 409 });
    }
    if (request.method === "POST" && url.pathname === "/internal/run") {
      const started = startRun();
      return Response.json({ started }, { status: started ? 202 : 409 });
    }
    return new Response("Not found", { status: 404 });
  },
});
console.log(`TCStock control server is ready on 127.0.0.1:${process.env.TCSTOCK_CONTROL_PORT || 8081}`);
