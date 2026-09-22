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

  it("publishes registration policy without authentication", async () => {
    const response = await app.request("/v1/config");
    expect(response.status).toBe(200);
    expect((await response.json()).registrationEnabled).toBe(true);
  });
});
