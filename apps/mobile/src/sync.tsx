import { AppState } from "react-native";
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import { compatibilityMessage, serverConfig, sync } from "./api";
import { applySync, cursor, notifyChanged, pendingMutationCount, pendingOperations } from "./db";
import { useSession } from "./session";

export const SYNC_PAGE_SIZE = 500;

async function performSync(apiUrl: string, token: string) {
  const config = await serverConfig(apiUrl);
  const message = compatibilityMessage(config);
  const canSync = message === "App and server are compatible" || message.startsWith("App update available");
  if (!canSync) throw new Error(message);

  const operations = pendingOperations();
  let result = await sync(apiUrl, token, cursor(), operations);
  applySync(result);

  // A full page means there is more history waiting.
  let guard = 0;
  while (result.changes.length >= SYNC_PAGE_SIZE && guard < 20) {
    result = await sync(apiUrl, token, cursor(), []);
    applySync(result);
    guard += 1;
  }
}

type SyncValue = {
  isSyncing: boolean;
  isOffline: boolean;
  lastError: string | null;
  lastSyncedAt: string | null;
  pendingCount: number;
  refresh: () => Promise<void>;
};

const SyncContext = createContext<SyncValue | null>(null);

export function SyncProvider({ children }: { children: React.ReactNode }) {
  const { apiUrl, token, localOnly } = useSession();
  const [isSyncing, setIsSyncing] = useState(false);
  const [isOffline, setIsOffline] = useState(false);
  const [lastError, setLastError] = useState<string | null>(null);
  const [lastSyncedAt, setLastSyncedAt] = useState<string | null>(null);
  const [pendingCount, setPendingCount] = useState(0);
  const running = useRef(false);
  const lastRun = useRef(0);

  const refresh = useCallback(async () => {
    if (!token || localOnly || running.current) {
      setPendingCount(pendingMutationCount());
      return;
    }
    running.current = true;
    setIsSyncing(true);
    try {
      await performSync(apiUrl, token);
      setIsOffline(false);
      setLastError(null);
      setLastSyncedAt(new Date().toISOString());
    } catch (error) {
      setIsOffline(true);
      setLastError(error instanceof Error ? error.message : "The server is unreachable.");
    } finally {
      running.current = false;
      setIsSyncing(false);
      setPendingCount(pendingMutationCount());
      lastRun.current = Date.now();
      notifyChanged();
    }
  }, [apiUrl, localOnly, token]);

  useEffect(() => {
    if (!token || localOnly) return;
    void refresh();
    const subscription = AppState.addEventListener("change", (state) => {
      if (state === "active" && Date.now() - lastRun.current > 60_000) void refresh();
    });
    return () => subscription.remove();
  }, [localOnly, refresh, token]);

  const value = useMemo(
    () => ({ isSyncing, isOffline, lastError, lastSyncedAt, pendingCount, refresh }),
    [isOffline, isSyncing, lastError, lastSyncedAt, pendingCount, refresh],
  );

  return <SyncContext.Provider value={value}>{children}</SyncContext.Provider>;
}

export function useSync(): SyncValue {
  const value = useContext(SyncContext);
  if (!value) throw new Error("SyncProvider missing");
  return value;
}
