import type { SyncOperation, SyncResponse } from "./types";

export const APP_VERSION = "0.6.20";
export const SYNC_PROTOCOL_VERSION = 2;

export type AuthResponse = {
  token: string;
  user: { username: string };
  context: { apiUrl: string; convexUrl: string; syncSessionId: string; expiresAt: string };
};

export type ServerConfig = {
  registrationEnabled: boolean;
  convexUrl: string;
  serverVersion?: string | null;
  syncProtocolVersion?: number | null;
  minimumAppVersion?: string | null;
  latestAppVersion?: string | null;
};

export type APIKeySummary = { id: string; name: string; prefix: string; createdAt: number };
export type CreatedAPIKey = APIKeySummary & { key: string };

export class APIError extends Error {
  status: number;
  constructor(message: string, status = 0) {
    super(message);
    this.status = status;
  }
}

const trim = (url: string) => url.trim().replace(/\/$/, "");

async function request<T>(
  apiUrl: string,
  path: string,
  options: { method?: string; body?: unknown; token?: string | null } = {},
): Promise<T> {
  const { method = "GET", body, token } = options;
  let response: Response;
  try {
    response = await fetch(`${trim(apiUrl)}${path}`, {
      method,
      headers: {
        ...(body ? { "Content-Type": "application/json" } : {}),
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw new APIError("The server is unreachable.");
  }
  if (!response.ok) {
    let message: string | undefined;
    try {
      const parsed = (await response.json()) as { message?: string; error?: string };
      message = parsed.message ?? parsed.error;
    } catch {
      const text = (await response.text().catch(() => "")).trim();
      message = text || undefined;
    }
    throw new APIError(message ?? `Server request failed (${response.status}).`, response.status);
  }
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

export async function serverConfig(apiUrl: string): Promise<ServerConfig> {
  return request<ServerConfig>(apiUrl, "/v1/config");
}

export async function authenticate(
  apiUrl: string,
  username: string,
  password: string,
  convexUrl: string,
  register = false,
): Promise<AuthResponse> {
  const body = { username, password, convexUrl };
  if (register) await request(apiUrl, "/v1/auth/register", { method: "POST", body });
  return request<AuthResponse>(apiUrl, "/v1/auth/login", { method: "POST", body });
}

export async function logout(apiUrl: string, token: string | null) {
  if (!token) return;
  try {
    await request(apiUrl, "/v1/auth/logout", { method: "POST", token });
  } catch {
    // Logging out locally still works when the server is unreachable.
  }
}

export async function sync(
  apiUrl: string,
  token: string,
  cursor: string | undefined,
  operations: SyncOperation[],
): Promise<SyncResponse> {
  return request<SyncResponse>(apiUrl, "/v1/sync", {
    method: "POST",
    token,
    body: { protocolVersion: SYNC_PROTOCOL_VERSION, cursor: cursor ?? "0", operations, appVersion: APP_VERSION },
  });
}

export async function healthReady(apiUrl: string) {
  await request(apiUrl, "/health/ready");
}

export async function listAPIKeys(apiUrl: string, token: string) {
  return request<APIKeySummary[]>(apiUrl, "/v1/api-keys", { token });
}

export async function createAPIKey(apiUrl: string, token: string, name: string) {
  return request<CreatedAPIKey>(apiUrl, "/v1/api-keys", { method: "POST", token, body: { name } });
}

export async function revokeAPIKey(apiUrl: string, token: string, id: string) {
  await request(apiUrl, `/v1/api-keys/${id}`, { method: "DELETE", token });
}

/** Mirrors ServerCompatibility.swift: the sync protocol must match exactly. */
export function compatibilityMessage(config: ServerConfig): string {
  if (!config.serverVersion || config.syncProtocolVersion == null) return "Server update required";
  if (config.syncProtocolVersion !== SYNC_PROTOCOL_VERSION) {
    return `Sync protocol mismatch (server ${config.syncProtocolVersion}, app ${SYNC_PROTOCOL_VERSION})`;
  }
  const compare = (a: string, b: string) => a.localeCompare(b, undefined, { numeric: true });
  if (config.minimumAppVersion && compare(APP_VERSION, config.minimumAppVersion) < 0) {
    return `Update the app to ${config.minimumAppVersion} or newer`;
  }
  if (config.latestAppVersion && compare(APP_VERSION, config.latestAppVersion) < 0) {
    return `App update available: ${config.latestAppVersion}`;
  }
  return "App and server are compatible";
}
