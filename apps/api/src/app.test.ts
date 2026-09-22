import { describe, expect, it } from "bun:test";

process.env.API_TOKEN = "test-token-at-least-16-characters";
const { app } = await import("./app");

describe("health", () => {
  it("reports liveness without database access", async () => {
    const response = await app.request("/health/live");
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ status: "ok" });
  });

  it("protects versioned routes", async () => {
    const response = await app.request("/v1/accounts");
    expect(response.status).toBe(401);
  });
});
