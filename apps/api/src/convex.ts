import { ConvexHttpClient } from "convex/browser";
import { config } from "./config";

export const convex = new ConvexHttpClient(config.CONVEX_URL);

export async function convexQuery<T>(name: string, args: Record<string, unknown>): Promise<T> {
  return convex.query(name as never, args as never) as Promise<T>;
}

export async function convexMutation<T>(name: string, args: Record<string, unknown>): Promise<T> {
  return convex.mutation(name as never, args as never) as Promise<T>;
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export function normalizedURL(value: string): string {
  const url = new URL(value);
  url.pathname = url.pathname.replace(/\/$/, "");
  url.search = "";
  url.hash = "";
  return url.toString().replace(/\/$/, "");
}
