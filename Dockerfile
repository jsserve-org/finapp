FROM oven/bun:1.4.2-alpine AS dependencies
WORKDIR /app

COPY package.json bun.lock ./
COPY apps/api/package.json apps/api/package.json
COPY apps/android/package.json apps/android/package.json
COPY packages/contracts/package.json packages/contracts/package.json
RUN bun install --frozen-lockfile

FROM oven/bun:1.4.2-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY --from=dependencies --chown=bun:bun /app/node_modules ./node_modules
COPY --from=dependencies --chown=bun:bun /app/apps/api/node_modules ./apps/api/node_modules
COPY --chown=bun:bun package.json bun.lock ./
COPY --chown=bun:bun apps/api ./apps/api
COPY --chown=bun:bun packages/contracts ./packages/contracts

USER bun
EXPOSE 3000
CMD ["bun", "apps/api/src/index.ts"]
