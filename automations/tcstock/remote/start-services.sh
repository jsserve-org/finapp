#!/bin/bash
set -euo pipefail
cd /app
export DISPLAY=:99

Xvfb :99 -screen 0 1280x800x24 -nolisten tcp > /app/run/xvfb.log 2>&1 &
xvfb_pid=$!
sleep 1
x11vnc -display :99 -forever -shared -localhost -nopw -rfbport 5900 > /app/run/x11vnc.log 2>&1 &
vnc_pid=$!
websockify --web=/usr/share/novnc 127.0.0.1:6081 127.0.0.1:5900 > /app/run/websockify.log 2>&1 &
websocket_pid=$!
browser_executable=$(bun -e 'import { chromium } from "playwright"; console.log(chromium.executablePath())')
"$browser_executable" \
  --no-sandbox \
  --disable-dev-shm-usage \
  --no-first-run \
  --no-default-browser-check \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port=9223 \
  --user-data-dir=/app/profile \
  --window-size=1280,800 \
  https://www.tcstock.com.tw/TCS/ > /app/run/browser.log 2>&1 &
browser_pid=$!
bun run src/control.ts > /app/run/control.log 2>&1 &
control_pid=$!
nginx -c /app/remote/nginx.conf -g 'daemon off;' &
nginx_pid=$!

cleanup() {
  kill "$nginx_pid" "$control_pid" "$browser_pid" "$websocket_pid" "$vnc_pid" "$xvfb_pid" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM
wait -n "$nginx_pid" "$control_pid" "$browser_pid" "$websocket_pid" "$vnc_pid" "$xvfb_pid"
exit 1
