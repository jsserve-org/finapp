# TCStock statement fetcher

This Bun automation visits the TCStock portal and saves stock records as private JSON under `output/`. It writes `trades-YYYY-MM-DD.json` for the most recent 30 days of securities transactions, and `statement-YYYY-MM.json` for the previous month's securities statement when one is available. A repeat run replaces that day's or month's file atomically. When `LEDGERLY_API_URL` and `LEDGERLY_API_KEY` are set, each run imports new securities trades and derives Ledgerly holdings from the complete imported trade history. Run a historical backfill first so positions and net worth are complete.

The site runs reCAPTCHA v3 and may ask for interactive v2 image verification. This script lets the site's normal verification run and pauses for a person when v2 appears. GPT-6-Luna or GPT-5.6-Luna via OpenRouter is only for a **separate plain image code on a login form**, if one exists. It cannot complete reCAPTCHA. You may enter credentials in Chrome or set `TCSTOCK_IDNO` and `TCSTOCK_PASSWORD` in the private `.env` for automatic login. Jev does not handle login, CAPTCHA, trading, or account changes. The runner does not bypass reCAPTCHA or TWCA mobile verification; you complete those steps in the browser.

Playwright handles the known read-only controls directly. If a locator fails, Jev's official TypeSafe API chooses only among redacted read-only control labels. Jev does not receive trade rows, credentials, or the full page. The authenticated portal uses nested frames. Its `帳務查詢` → `證券對帳單` query and `帳務查詢` → `對帳單` monthly statement form were inspected.

## Setup

```sh
cd automations/tcstock
bun install
cp .env.example .env
bun run start
```

Set `TYPESAFE_API_KEY` in `.env` for Jev navigation fallback. Set `OPENROUTER_API_KEY` only if the site also displays a separate login image code, then configure `TCSTOCK_IMAGE_CODE_SELECTOR` and `TCSTOCK_IMAGE_INPUT_SELECTOR`. `OPENROUTER_CAPTCHA_MODEL` accepts `openai/gpt-6-luna` or `openai/gpt-5.6-luna` if available to your OpenRouter account.

For Ledgerly import, set `LEDGERLY_API_URL` and a Ledgerly API key in the private `.env`. The importer uses stable trade IDs and skips trades already present. A first-time historical backfill can use `TCSTOCK_TRADES_START_DATE=YYYY-MM-DD` for a one-off run; that writes `trades-YYYY-MM-DD-to-YYYY-MM-DD.json`. You can import a saved file with `bun run import:trades output/<trades-file>.json`. Scheduled runs normally use the latest 30 days.

The first run opens Chrome for you to complete reCAPTCHA and sign in, unless the gate passes automatically and credentials are configured. A headed Chrome test reached the login form through reCAPTCHA v3. The script checks the signed-in portal before opening login again. A persistent Chrome profile in `profile/` retains TCStock cookies and TWCA browser storage, including any site-issued trusted-device state; protect this directory as sensitive and do not copy individual TWCA keys into `.env`. We verified that an authenticated session survived a Docker container restart using the persistent profile. TCStock can still require mobile verification again when its server-side trust or session lease expires. `output/`, `profile/`, `.env`, and dependencies are Git ignored. Each JSON snapshot has a timestamp, source, period, and displayed table headers and rows. It contains financial information.

## Cron on the server

Set `STOCK_CRON` to a five-field cron expression in the server's `.env`, and set the server timezone to `Asia/Taipei` if that is the intended schedule. Then run:

```sh
bun run cron:install
```

This installs or replaces only the marked TCStock entry in the current user's crontab. Cron runs from this directory so Bun loads `.env`, and creates its log with a private umask. Set both credential variables for unattended sign-in. `TCSTOCK_HEADLESS=true` is suitable only if the site accepts its reCAPTCHA v3 score; a headless test was sent to interactive v2. With the default headed mode, `bun run cron:run` uses `xvfb-run` when a Linux server has no `DISPLAY`. Install Xvfb on that server first. A virtual display can still get a v2 challenge, and mobile verification may recur after a trusted session expires. Those runs exit with `ACTION_REQUIRED` in `cron.log`; they cannot be made fully unattended by Luna or Jev. When that happens, sign in interactively on the server with the same `profile/` directory. The server needs Chrome and Bun installed for the cron user.

The schedule is interpreted by the server's cron daemon. Setting `TZ` in this script's `.env` changes the process timezone, not the daemon's schedule. Configure the server or cron daemon timezone as needed. No cron entry is installed until `bun run cron:install` is invoked on that server.

## Remote browser on a private VPN server

This mode keeps one headed Chromium browser running in a container. Chromium starts directly, and Playwright attaches through CDP only when a sync begins. Its profile and the exported JSON files live in the host directories `remote-profile/` and `output/`. The control page embeds a noVNC view of that browser, so you can complete reCAPTCHA, enter your phone number, and approve any TWCA mobile verification yourself. Then click **Run sync now**. Scheduled runs attach to this same browser and normally reuse the signed-in session and TWCA trust. Set `TCSTOCK_AUTO_LOGIN=true` with `TCSTOCK_IDNO` and `TCSTOCK_PASSWORD` to fill and submit a visible login form automatically after the session expires. If TCStock presents reCAPTCHA or asks for renewed TWCA approval, the run leaves the browser for you and writes `ACTION_REQUIRED` to `output/runner.log`. Direct launch avoids Playwright's automation launch flags but does not guarantee that TCStock will accept a challenge.

On the server, copy `.env.example` to `.env`, set a strong `TCSTOCK_WEB_USER` and `TCSTOCK_WEB_PASSWORD`, and set `TCSTOCK_BIND_IP` to the server's private VPN address. Leave `TCSTOCK_BIND_IP=127.0.0.1` for laptop-only access or an SSH tunnel over the VPN. Do not bind it to a public interface. Keep `.env`, `remote-profile/`, and `output/` private; the profile can contain broker and trusted-device state. Use VPN transport or HTTPS for remote access because Basic Auth itself does not encrypt traffic.

```sh
cd automations/tcstock
cp .env.example .env
# Edit .env on the server, then:
docker compose -f compose.yml up -d --build
```

With a VPN bind address, visit `http://<server-vpn-ip>:8080/`. With the loopback default, tunnel `ssh -L 8080:127.0.0.1:8080 <server-vpn-host>` and visit `http://127.0.0.1:8080/`. The web password protects both the control page and browser view. Docker's internal CDP port is not published. The browser remains open when a sync finishes.

Set `STOCK_CRON` to your chosen five-field expression in the server's `.env`, ensure the host cron daemon schedules in `Asia/Taipei`, then run `bun run cron:install:remote` on the server. This installs one marked **host** cron entry that calls the container's local control endpoint; it does not create an additional browser. The control endpoint cannot be reached through the web page. If the container is down, that cron attempt is logged to `cron.log`. The actual extraction result is in `output/runner.log`. No schedule is installed merely by starting Compose.

## Native Chrome on a laptop

If TCStock repeatedly rejects CAPTCHA attempts inside noVNC, use a separate native Chrome profile on the laptop. Close the Compose service with `docker compose -f compose.yml down`, then launch Chrome with `--user-data-dir` pointing to `native-profile/` and `--remote-debugging-port=9223`. Start the control server with `TCSTOCK_LOCAL_BROWSER=true TCSTOCK_CONTROL_PORT=18080 bun run src/control.ts`. Open `http://127.0.0.1:18080/` for the sync button, and complete login and verification in the separate Chrome window. The control server attaches to that Chrome instance through CDP and saves the same JSON exports. Keep this Chrome window open for subsequent syncs. This local control page only listens on laptop loopback and has no web password.
