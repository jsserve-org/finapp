import type { SyncResponse } from "@ledgerly/contracts";
import { applySync, cursor } from "./db";

const apiUrl = process.env.EXPO_PUBLIC_API_URL ?? "http://10.0.2.2:3000";
const token = process.env.EXPO_PUBLIC_API_TOKEN ?? "local-development-token";

export async function syncNow(): Promise<SyncResponse> {
  const response = await fetch(`${apiUrl}/v1/sync`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ cursor: cursor(), operations: [] }),
  });
  if (!response.ok) throw new Error(`Sync failed (${response.status})`);
  const body = await response.json() as SyncResponse;
  applySync(body);
  return body;
}
