FROM oven/bun:1.4.2 AS bun

FROM mcr.microsoft.com/playwright:v1.63.0-noble
COPY --from=bun /usr/local/bin/bun /usr/local/bin/bun

RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2-utils gosu nginx novnc websockify x11vnc xvfb \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/bash tcstock

WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY src ./src
COPY remote ./remote
RUN chmod +x /app/remote/*.sh && mkdir -p /app/profile /app/output /app/run

ENV NODE_ENV=production DISPLAY=:99 TCSTOCK_BROWSER_CHANNEL=chromium \
    TCSTOCK_PROFILE_DIR=/app/profile TCSTOCK_OUTPUT_DIR=/app/output
EXPOSE 8080
ENTRYPOINT ["/app/remote/entrypoint.sh"]
