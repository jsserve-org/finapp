import type { SyncResponse } from "@ledgerly/contracts";
import { acceptMutations, applySync, cursor, pendingOperations } from "./db";
import * as SecureStore from "expo-secure-store";
import { endpoint, type AuthResponse } from "./session";

const defaultApiUrl = process.env.EXPO_PUBLIC_API_URL ?? "http://10.0.2.2:3000";

export async function serverConfig(apiUrl: string): Promise<{ registrationEnabled: boolean; convexUrl: string }> {
  const response = await fetch(`${apiUrl.replace(/\/$/, "")}/v1/config`);
  if (!response.ok) throw new Error("Server configuration unavailable");
  return response.json();
}

export async function authenticate(apiUrl: string, convexUrl: string, username: string, password: string, register = false): Promise<AuthResponse | null> {
  const response = await fetch(`${apiUrl.replace(/\/$/, "")}/v1/auth/${register ? "register" : "login"}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ username, password, convexUrl }) });
  if (!response.ok) throw new Error(response.status === 401 ? "Invalid username or password" : `Server rejected the request (${response.status})`);
  return register ? null : response.json() as Promise<AuthResponse>;
}

export async function syncNow(): Promise<SyncResponse> {
  const apiUrl = await endpoint("api-url", defaultApiUrl);
  const token = await SecureStore.getItemAsync("session-token");
  if (!token) throw new Error("Not logged in");
  const response = await fetch(`${apiUrl}/v1/sync`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ cursor: cursor(), operations: pendingOperations() }),
  });
  if (!response.ok) throw new Error(`Sync failed (${response.status})`);
  const body = await response.json() as SyncResponse;
  acceptMutations(body.acceptedMutationIds);
  applySync(body);
  return body;
}
