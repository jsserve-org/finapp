import * as SecureStore from "expo-secure-store";
import { createContext, useContext, useEffect, useMemo, useState } from "react";

type SessionContextValue = { token: string | null; localOnly: boolean; loading: boolean; login(response: AuthResponse): Promise<void>; continueLocally(): Promise<void>; configureSync(): Promise<void>; logout(): Promise<void> };
export type AuthResponse = { token: string; user: { username: string }; context: { apiUrl: string; convexUrl: string; syncSessionId: string; expiresAt: string } };
const SessionContext = createContext<SessionContextValue | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [token, setToken] = useState<string | null>(null);
  const [localOnly, setLocalOnly] = useState(false);
  const [loading, setLoading] = useState(true);
  useEffect(() => { Promise.all([SecureStore.getItemAsync("session-token"), SecureStore.getItemAsync("local-only")]).then(([savedToken, local]) => { setToken(savedToken); setLocalOnly(local === "true"); }).finally(() => setLoading(false)); }, []);
  const value = useMemo(() => ({ token, localOnly, loading,
    login: async (response: AuthResponse) => {
      await SecureStore.setItemAsync("session-token", response.token);
      await SecureStore.setItemAsync("api-url", response.context.apiUrl);
      await SecureStore.setItemAsync("convex-url", response.context.convexUrl);
      await SecureStore.setItemAsync("sync-session-id", response.context.syncSessionId);
      await SecureStore.deleteItemAsync("local-only"); setLocalOnly(false);
      setToken(response.token);
    },
    continueLocally: async () => { await SecureStore.setItemAsync("local-only", "true"); setLocalOnly(true); },
    configureSync: async () => { await SecureStore.deleteItemAsync("local-only"); setLocalOnly(false); },
    logout: async () => {
      try {
        const apiUrl = await endpoint("api-url", process.env.EXPO_PUBLIC_API_URL ?? "http://10.0.2.2:3000");
        if (token) await fetch(`${apiUrl}/v1/auth/logout`, { method: "POST", headers: { Authorization: `Bearer ${token}` } });
      } finally { await SecureStore.deleteItemAsync("session-token"); setToken(null); }
    },
  }), [token, localOnly, loading]);
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession() { const value = useContext(SessionContext); if (!value) throw new Error("SessionProvider missing"); return value; }
export const endpoint = async (key: "api-url" | "convex-url", fallback: string) => (await SecureStore.getItemAsync(key)) ?? fallback;
