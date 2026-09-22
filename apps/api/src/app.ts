import { and, desc, eq, sql } from "drizzle-orm";
import { Hono } from "hono";
import { bearerAuth } from "hono/bearer-auth";
import { HTTPException } from "hono/http-exception";
import { DemoBankProvider } from "./automation/provider";
import { runConnection } from "./automation/service";
import { config } from "./config";
import { db } from "./db";
import { accounts, bankConnections, transactions, users } from "./db/schema";
import { serializeAccount, serializeTransaction } from "./domain/serializers";
import { syncRoutes } from "./routes/sync";

export const app = new Hono<{ Variables: { userId: string } }>();

app.get("/health/live", (c) => c.json({ status: "ok" }));
app.get("/health/ready", async (c) => {
  try { await db.execute(sql`select 1`); return c.json({ status: "ready" }); }
  catch { return c.json({ status: "unavailable" }, 503); }
});

app.use("/v1/*", bearerAuth({ token: config.API_TOKEN }));
app.use("/v1/*", async (c, next) => {
  // Development identity boundary. Replace with verified OIDC `sub` before multi-user deployment.
  const [user] = await db.insert(users).values({ externalId: "local-user" }).onConflictDoUpdate({ target: users.externalId, set: { externalId: "local-user" } }).returning();
  c.set("userId", user.id);
  await next();
});

app.get("/v1/accounts", async (c) => {
  const rows = await db.select().from(accounts).where(eq(accounts.userId, c.get("userId"))).orderBy(accounts.name);
  return c.json(rows.map(serializeAccount));
});

app.get("/v1/transactions", async (c) => {
  const rows = await db.select().from(transactions).where(and(eq(transactions.userId, c.get("userId")), eq(transactions.pending, false))).orderBy(desc(transactions.bookedAt)).limit(200);
  return c.json(rows.filter((row) => !row.deletedAt).map(serializeTransaction));
});

app.route("/v1/sync", syncRoutes);

app.post("/v1/automations/demo/run", async (c) => {
  const userId = c.get("userId");
  const [connection] = await db.insert(bankConnections).values({ userId, provider: "demo", providerItemId: `demo-${userId}` })
    .onConflictDoUpdate({ target: [bankConnections.provider, bankConnections.providerItemId], set: { updatedAt: new Date() } }).returning();
  const result = await runConnection(connection.id, userId, new DemoBankProvider());
  return c.json(result, 202);
});

app.get("/v1/automations/status", async (c) => {
  const rows = await db.select().from(bankConnections).where(eq(bankConnections.userId, c.get("userId")));
  return c.json(rows.map((row) => ({ connectionId: row.id, state: row.status, lastSuccessAt: row.lastSuccessAt?.toISOString(), lastError: row.lastError ?? undefined, nextCheckAt: row.nextCheckAt.toISOString() })));
});

app.onError((error, c) => {
  if (error instanceof HTTPException) return error.getResponse();
  console.error(JSON.stringify({ event: "request_error", message: error.message }));
  return c.json({ error: "internal_error", requestId: c.req.header("x-request-id") }, 500);
});
