import { afterEach, describe, expect, it, mock, spyOn } from "bun:test";
import type { SyncRequest } from "@ledgerly/contracts";

process.env.CONVEX_URL = "http://localhost:3210";
const { app } = await import("./app");
const { convex } = await import("./convex");

afterEach(() => mock.restore());

describe("sync validation", () => {
  it("returns an actionable 400 when backend record validation fails", async () => {
    spyOn(convex, "query").mockResolvedValue({ userId: "user", username: "tester", syncSessionId: "session" });
    spyOn(convex, "mutation").mockRejectedValue(new Error("INVALID_SYNC_VALUE: recurringPayment bad-bill"));
    const response = await app.request("/v1/sync", { method: "POST", headers: { authorization: "Bearer test", "content-type": "application/json" }, body: JSON.stringify({ protocolVersion: 2, operations: [] }) });
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ error: "Invalid sync record", message: "INVALID_SYNC_VALUE: recurringPayment bad-bill" });
  });
  it("accepts offset ISO timestamps for both bill types", async () => {
    spyOn(convex, "query").mockResolvedValue({ userId: "user", username: "tester", syncSessionId: "session" });
    const mutation = spyOn(convex, "mutation").mockResolvedValue({ id: "bill", created: true });
    for (const fields of [{ type: "oneTime", date: "2026-10-01T00:00:00+08:00" }, { type: "recurring", nextDate: "2026-10-05T00:00:00.000+08:00", frequency: "monthly" }]) {
      const response = await app.request("/v1/bills", { method: "POST", headers: { authorization: "Bearer test", "content-type": "application/json" }, body: JSON.stringify({ ...fields, name: "Bill", amountMinor: 100, currency: "TWD", accountId: "cash" }) });
      expect(response.status).toBe(201);
    }
    expect(mutation).toHaveBeenCalledTimes(2);
  });
  function authenticate() {
    spyOn(convex, "query").mockResolvedValue({ userId: "user", username: "tester", syncSessionId: "session" });
    return spyOn(convex, "mutation").mockResolvedValue({ cursor: "0", changes: [], acceptedMutationIds: [] });
  }
  function sync(body: string) {
    return app.request("/v1/sync", { method: "POST", headers: { authorization: "Bearer test", "content-type": "application/json" }, body });
  }

  it("rejects malformed requests before calling the backend", async () => {
    const mutation = authenticate();
    for (const body of ["null", "{", JSON.stringify({ protocolVersion: 2, operations: "oops" }), JSON.stringify({ protocolVersion: 2, cursor: 4 }), JSON.stringify({ protocolVersion: 2, operations: [{ mutationId: "m", entity: "garbage", action: "delete", entityId: "tx", baseVersion: 0 }] })]) {
      expect((await sync(body)).status).toBe(400);
    }
    expect(mutation).not.toHaveBeenCalled();
  });

  it("accepts the published request contract", async () => {
    const mutation = authenticate();
    const body: SyncRequest = { protocolVersion: 2, operations: [] };
    expect((await sync(JSON.stringify(body))).status).toBe(200);
    expect(mutation).toHaveBeenCalledTimes(1);
  });

  it("keeps the upgrade response for unsupported protocols", async () => {
    const mutation = authenticate();
    expect((await sync(JSON.stringify({ protocolVersion: 1, operations: [] }))).status).toBe(426);
    expect(mutation).not.toHaveBeenCalled();
  });
});

describe("health", () => {
  it("reports liveness without database access", async () => {
    const response = await app.request("/health/live");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("protects sync routes", async () => {
    const response = await app.request("/v1/accounts");
    expect(response.status).toBe(401);
    expect((await app.request("/v1/dashboard")).status).toBe(401);
  });

  it("protects bill creation and account lookup", async () => {
    expect((await app.request("/v1/accounts")).status).toBe(401);
    expect((await app.request("/v1/bills", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" })).status).toBe(401);
  });

  it("protects API key management", async () => {
    expect((await app.request("/v1/api-keys")).status).toBe(401);
    expect((await app.request("/v1/api-keys", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name: "Agent" }) })).status).toBe(401);
    expect((await app.request("/v1/api-keys/key-id", { method: "DELETE" })).status).toBe(401);
  });

  it("publishes registration policy without authentication", async () => {
    const response = await app.request("/v1/config");
    expect(response.status).toBe(200);
    const body = await response.json();
    expect(body.registrationEnabled).toBe(true);
    expect(body.serverVersion).toBe("0.6.12");
    expect(body.syncProtocolVersion).toBe(2);
    expect(body.minimumAppVersion).toBe("0.4.0");
    expect(body.latestAppVersion).toBe("0.6.12");
  });
});
