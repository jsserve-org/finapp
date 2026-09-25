#!/bin/sh
set -eu
: "${TCSTOCK_WEB_USER:?Set TCSTOCK_WEB_USER for browser access}"
: "${TCSTOCK_WEB_PASSWORD:?Set TCSTOCK_WEB_PASSWORD for browser access}"
mkdir -p /app/profile /app/output /app/run
chown -R tcstock:tcstock /app/profile /app/output /app/run
chmod 700 /app/profile /app/output /app/run
rm -f /app/profile/SingletonLock /app/profile/SingletonCookie /app/profile/SingletonSocket
printf '%s\n' "$TCSTOCK_WEB_PASSWORD" | htpasswd -iBc /app/run/htpasswd "$TCSTOCK_WEB_USER" >/dev/null
chown tcstock:tcstock /app/run/htpasswd
chmod 600 /app/run/htpasswd
exec gosu tcstock /app/remote/start-services.sh
