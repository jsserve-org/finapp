export type Money = { amountMinor: number; currency: string };

export type Account = {
  id: string;
  name: string;
  institution: string;
  kind: "checking" | "savings" | "credit" | "investment" | "cash";
  balance: Money;
  updatedAt: string;
};

export type Transaction = {
  id: string;
  accountId: string;
  description: string;
  amount: Money;
  bookedAt: string;
  pending: boolean;
  category?: string;
  updatedAt: string;
};

export type SyncOperation = {
  mutationId: string;
  entity: "account" | "transaction" | "recurringPayment" | "stockHolding" | "stockTrade";
  action: "upsert" | "delete";
  entityId: string;
  value?: Account | Partial<Pick<Transaction, "description" | "category">>;
  baseVersion: number;
};

export type SyncRequest = { cursor?: string; operations: SyncOperation[] };
export type SyncChange = {
  sequence: number;
  entity: "account" | "transaction" | "recurringPayment" | "stockHolding" | "stockTrade";
  entityId: string;
  action: "upsert" | "delete";
  value: Account | Transaction | null;
};
export type SyncResponse = { cursor: string; changes: SyncChange[]; acceptedMutationIds: string[] };

export type AutomationStatus = {
  connectionId: string;
  state: "healthy" | "degraded" | "action_required" | "running";
  lastSuccessAt?: string;
  lastError?: string;
  nextCheckAt: string;
};
