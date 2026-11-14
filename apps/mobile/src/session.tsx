import * as SecureStore from "expo-secure-store";
import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { Platform } from "react-native";
import type { AuthResponse } from "./api";

const fallbackHost = Platform.OS === "android" ? "10.0.2.2" : "localhost";
export const defaultApiUrl = process.env.EXPO_PUBLIC_API_URL ?? `http://${fallbackHost}:3000`;
export const defaultConvexUrl = process.env.EXPO_PUBLIC_CONVEX_URL ?? `http://${fallbackHost}:3210`;

type SessionValue = {
  token: string | null;
  localOnly: boolean;
  loading: boolean;
  apiUrl: string;
  convexUrl: string;
  username: string | null;
  canUseApp: boolean;
  login(response: AuthResponse, apiUrl: string, convexUrl: string): Promise<void>;
  continueLocally(): Promise<void>;
  configureSync(): Promise<void>;
  saveEndpoints(apiUrl: string, convexUrl: string): Promise<void>;
  logout(): Promise<void>;
};

const SessionContext = createContext<SessionValue | null>(null);

export function SessionProvider({ children }: { children: React.ReactNode }) {
  const [token, setToken] = useState<string | null>(null);
  const [localOnly, setLocalOnly] = useState(false);
  const [apiUrl, setApiUrl] = useState(defaultApiUrl);
  const [convexUrl, setConvexUrl] = useState(defaultConvexUrl);
  const [username, setUsername] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Promise.all([
      SecureStore.getItemAsync("session-token"),
      SecureStore.getItemAsync("local-only"),
      SecureStore.getItemAsync("api-url"),
      SecureStore.getItemAsync("convex-url"),
      SecureStore.getItemAsync("username"),
    ])
      .then(([savedToken, local, savedApiUrl, savedConvexUrl, savedUsername]) => {
        setToken(savedToken);
        setLocalOnly(local === "true");
        if (savedApiUrl) setApiUrl(savedApiUrl);
        if (savedConvexUrl) setConvexUrl(savedConvexUrl);
        setUsername(savedUsername);
      })
      .finally(() => setLoading(false));
  }, []);

  const login = useCallback(async (response: AuthResponse, nextApiUrl: string, nextConvexUrl: string) => {
    await Promise.all([
      SecureStore.setItemAsync("session-token", response.token),
      SecureStore.setItemAsync("api-url", nextApiUrl),
      SecureStore.setItemAsync("convex-url", nextConvexUrl),
      SecureStore.setItemAsync("sync-session-id", response.context.syncSessionId),
      SecureStore.setItemAsync("username", response.user.username),
      SecureStore.deleteItemAsync("local-only"),
    ]);
    setApiUrl(nextApiUrl);
    setConvexUrl(nextConvexUrl);
    setUsername(response.user.username);
    setLocalOnly(false);
    setToken(response.token);
  }, []);

  const value = useMemo<SessionValue>(
    () => ({
      token,
      localOnly,
      loading,
      apiUrl,
      convexUrl,
      username,
      canUseApp: token != null || localOnly,
      login,
      continueLocally: async () => {
        await SecureStore.setItemAsync("local-only", "true");
        setLocalOnly(true);
      },
      configureSync: async () => {
        await SecureStore.deleteItemAsync("local-only");
        setLocalOnly(false);
        setToken(null);
      },
      saveEndpoints: async (nextApiUrl: string, nextConvexUrl: string) => {
        await Promise.all([
          SecureStore.setItemAsync("api-url", nextApiUrl),
          SecureStore.setItemAsync("convex-url", nextConvexUrl),
        ]);
        setApiUrl(nextApiUrl);
        setConvexUrl(nextConvexUrl);
      },
      logout: async () => {
        await Promise.all([SecureStore.deleteItemAsync("session-token"), SecureStore.deleteItemAsync("sync-session-id")]);
        setToken(null);
      },
    }),
    [apiUrl, convexUrl, loading, localOnly, login, token, username],
  );

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): SessionValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("SessionProvider missing");
  return value;
}
