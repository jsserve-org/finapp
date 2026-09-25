import { describe, expect, it } from "bun:test";

process.env.CONVEX_URL = "http://localhost:3210";
const { app } = await import("./app");

describe("health", () => {
  it("reports liveness without database access", async () => {
    const response = await app.request("/health/live");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("protects sync routes", async () => {
    const response = await app.request("/v1/accounts");
    expect(response.status).toBe(401);
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
    expect(body.serverVersion).toBe("0.5.0");
    expect(body.syncProtocolVersion).toBe(2);
    expect(body.minimumAppVersion).toBe("0.4.0");
    expect(body.latestAppVersion).toBe("0.5.0");
  });
});
