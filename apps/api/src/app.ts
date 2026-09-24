import { zValidator } from "@hono/zod-validator";
import { Hono } from "hono";
import { HTTPException } from "hono/http-exception";
import { z } from "zod";
import { config } from "./config";
import { convexMutation, convexQuery, normalizedURL, sha256 } from "./convex";

type Session = { userId: string; username: string; syncSessionId: string };
type Variables = { sessionToken: string; session: Session };
export const app = new Hono<{ Variables: Variables }>();

app.use("*", async (c, next) => {
  const startedAt = performance.now();
  await next();
  console.log(JSON.stringify({
    event: "request",
    method: c.req.method,
    path: c.req.path,
    status: c.res.status,
    durationMs: Math.round(performance.now() - startedAt),
  }));
});

const credentials = z.object({
  username: z.string().trim().toLowerCase().regex(/^[a-z0-9_.-]{3,40}$/),
  password: z.string().min(10).max(128),
  convexUrl: z.string().url(),
});

const currency = z.enum(["TWD", "USD", "JPY", "PHP", "EUR", "GBP", "CNY", "HKD", "SGD", "KRW", "AUD", "CAD", "THB", "MYR", "VND", "INR", "IDR"]);
const apiKeyName = z.object({ name: z.string().trim().min(1).max(80) });
const bill = z.discriminatedUnion("type", [
  z.object({
    id: z.string().uuid().optional(), type: z.literal("oneTime"), name: z.string().trim().min(1).max(120),
    amountMinor: z.number().int().positive(), currency, date: z.string().datetime(),
    accountId: z.string().min(1), category: z.string().trim().min(1).max(80).default("Bills"),
  }),
  z.object({
    id: z.string().uuid().optional(), type: z.literal("recurring"), name: z.string().trim().min(1).max(120),
    amountMinor: z.number().int().positive(), currency, frequency: z.enum(["weekly", "everyTwoWeeks", "monthly", "yearly"]),
    nextDate: z.string().datetime(), accountId: z.string().min(1).optional(), category: z.string().trim().min(1).max(80).default("Bills"),
  }),
]);

function requireDeployment(requested: string) {
  if (normalizedURL(requested) !== normalizedURL(config.PUBLIC_CONVEX_URL)) {
    throw new HTTPException(400, { message: "The Convex URL does not belong to this API server" });
  }
}

app.get("/health/live", (c) => c.json({ status: "ok" }));
app.get("/v1/config", (c) => c.json({ registrationEnabled: config.ALLOW_REGISTRATION, convexUrl: normalizedURL(config.PUBLIC_CONVEX_URL) }));
app.get("/health/ready", async (c) => {
  try {
    await convexQuery("system:health", {});
    return c.json({ status: "ready", convexUrl: normalizedURL(config.PUBLIC_CONVEX_URL) });
  } catch { return c.json({ status: "unavailable" }, 503); }
});

app.post("/v1/auth/register", zValidator("json", credentials), async (c) => {
  if (!config.ALLOW_REGISTRATION) throw new HTTPException(403, { message: "Registration is disabled" });
  const body = c.req.valid("json");
  requireDeployment(body.convexUrl);
  const passwordHash = await Bun.password.hash(body.password, { algorithm: "argon2id", memoryCost: 65536, timeCost: 3 });
  try { await convexMutation("auth:createUser", { username: body.username, passwordHash, serviceSecret: config.API_SERVICE_SECRET }); }
  catch (error) {
    if (error instanceof Error && error.message.includes("USERNAME_TAKEN")) throw new HTTPException(409, { message: "Username is already registered" });
    throw error;
  }
  return c.json({ created: true }, 201);
});

app.post("/v1/auth/login", zValidator("json", credentials), async (c) => {
  const body = c.req.valid("json");
  requireDeployment(body.convexUrl);
  const credential = await convexQuery<{ userId: string; passwordHash: string } | null>("auth:getCredential", { username: body.username, serviceSecret: config.API_SERVICE_SECRET });
  if (!credential || !(await Bun.password.verify(body.password, credential.passwordHash))) throw new HTTPException(401, { message: "Invalid username or password" });
  const token = crypto.randomUUID() + crypto.randomUUID();
  const tokenHash = await sha256(token);
  const expiresAt = Date.now() + 30 * 24 * 60 * 60 * 1000;
  const context = { apiUrl: normalizedURL(config.PUBLIC_API_URL), convexUrl: normalizedURL(config.PUBLIC_CONVEX_URL) };
  const session = await convexMutation<{ syncSessionId: string }>("auth:createSession", { userId: credential.userId, tokenHash, expiresAt, serviceSecret: config.API_SERVICE_SECRET, context });
  return c.json({
    token, user: { username: body.username },
    context: { ...context, syncSessionId: session.syncSessionId, expiresAt: new Date(expiresAt).toISOString() },
  });
});

app.use("/v1/*", async (c, next) => {
  const authorization = c.req.header("authorization");
  if (!authorization?.startsWith("Bearer ")) throw new HTTPException(401, { message: "Missing session" });
  const token = authorization.slice(7);
  const session = await convexQuery<Session | null>("auth:validateSession", { tokenHash: await sha256(token), now: Date.now() });
  if (!session) throw new HTTPException(401, { message: "Session expired" });
  c.set("sessionToken", token); c.set("session", session); await next();
});

app.post("/v1/auth/logout", async (c) => {
  await convexMutation("auth:revokeSession", { tokenHash: await sha256(c.get("sessionToken")) });
  return c.body(null, 204);
});

app.post("/v1/sync", async (c) => {
  const body = await c.req.json().catch(() => ({ operations: [] }));
  return c.json(await convexMutation("sync:exchange", { tokenHash: await sha256(c.get("sessionToken")), cursor: body.cursor ?? "0", operations: body.operations ?? [], now: Date.now() }));
});

app.get("/v1/accounts", async (c) => c.json(await convexQuery("bills:listAccounts", { tokenHash: await sha256(c.get("sessionToken")), now: Date.now() })));

app.get("/v1/api-keys", async (c) => c.json(await convexQuery("apiKeys:list", { tokenHash: await sha256(c.get("sessionToken")), now: Date.now() })));

app.post("/v1/api-keys", zValidator("json", apiKeyName), async (c) => {
  const name = c.req.valid("json").name;
  const key = `ledgerly_${crypto.randomUUID().replaceAll("-", "")}${crypto.randomUUID().replaceAll("-", "")}`;
  const prefix = key.slice(0, 16);
  const record = await convexMutation<{ id: string; name: string; prefix: string; createdAt: number }>("apiKeys:create", {
    tokenHash: await sha256(c.get("sessionToken")), now: Date.now(), name, keyHash: await sha256(key), prefix,
  });
  return c.json({ ...record, key }, 201);
});

app.delete("/v1/api-keys/:id", async (c) => {
  await convexMutation("apiKeys:revoke", { tokenHash: await sha256(c.get("sessionToken")), now: Date.now(), id: c.req.param("id") });
  return c.body(null, 204);
});

app.post("/v1/bills", zValidator("json", bill), async (c) => {
  const input = c.req.valid("json");
  const id = input.id ?? crypto.randomUUID();
  const dateFields = input.type === "oneTime"
    ? { ...input, id }
    : { ...input, id, nextDate: (new Date(input.nextDate).getTime() - Date.UTC(2001, 0, 1)) / 1000 };
  try {
    return c.json(await convexMutation("bills:create", { tokenHash: await sha256(c.get("sessionToken")), now: Date.now(), bill: dateFields }), 201);
  } catch (error) {
    const message = error instanceof Error ? error.message : "";
    if (message.includes("ACCOUNT_NOT_FOUND")) throw new HTTPException(404, { message: "Account not found" });
    if (message.includes("CURRENCY_MISMATCH")) throw new HTTPException(409, { message: "Bill currency must match the account currency" });
    throw error;
  }
});

app.get("/v1/automations/status", async (c) => c.json(await convexQuery("automation:statuses", { tokenHash: await sha256(c.get("sessionToken")), now: Date.now() })));
app.post("/v1/automations/demo/run", async (c) => c.json(await convexMutation("automation:runDemo", { tokenHash: await sha256(c.get("sessionToken")), now: Date.now() }), 202));

app.onError((error, c) => {
  if (error instanceof HTTPException) return error.getResponse();
  console.error(JSON.stringify({ event: "request_error", message: error instanceof Error ? error.message : "unknown" }));
  return c.json({ error: "internal_error" }, 500);
});
