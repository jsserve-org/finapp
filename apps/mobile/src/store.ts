import { useEffect, useState } from "react";
import { getSetting, notifyChanged, setSetting, subscribe } from "./db";

/** Re-renders whenever local data or a sync changes the SQLite cache. */
export function useCacheVersion(): number {
  const [version, setVersion] = useState(0);
  useEffect(() => subscribe(() => setVersion((value) => value + 1)), []);
  return version;
}

const HIDE_AMOUNTS_KEY = "hideFinancialAmounts";

export function useHiddenAmounts(): [boolean, (next: boolean) => void] {
  const version = useCacheVersion();
  const [hidden, setHidden] = useState(() => getSetting(HIDE_AMOUNTS_KEY) === "true");
  useEffect(() => {
    setHidden(getSetting(HIDE_AMOUNTS_KEY) === "true");
  }, [version]);
  const update = (next: boolean) => {
    setSetting(HIDE_AMOUNTS_KEY, next ? "true" : "false");
    setHidden(next);
    notifyChanged();
  };
  return [hidden, update];
}

const QUICK_SPEND_ACCOUNT_KEY = "quickSpendAccountId";
const QUICK_SPEND_CATEGORY_KEY = "quickSpendCategory";

export const quickSpendState = {
  accountId: () => getSetting(QUICK_SPEND_ACCOUNT_KEY),
  setAccountId: (id: string) => setSetting(QUICK_SPEND_ACCOUNT_KEY, id),
  category: () => getSetting(QUICK_SPEND_CATEGORY_KEY) ?? "Dining",
  setCategory: (category: string) => setSetting(QUICK_SPEND_CATEGORY_KEY, category),
};
