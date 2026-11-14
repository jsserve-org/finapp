export type Money = { amountMinor: number; currency: string };

export type AccountKind = "checking" | "savings" | "credit" | "sharedCredit" | "investment" | "cash";

export type Account = {
  id: string;
  name: string;
  institution: string;
  kind: string;
  balance: Money;
  updatedAt: string;
};

export type Transaction = {
  id: string;
  accountId: string;
  description: string;
  amount: Money;
  originalAmount?: Money;
  bookedAt: string;
  pending: boolean;
  category?: string;
  categoryUserEdited?: boolean;
  recurringPaymentId?: string;
  source?: string;
  expensePurpose?: string;
  reimbursementStatus?: string;
  reimbursementTransactionId?: string;
  refundTransactionId?: string;
  refundedTransactionId?: string;
  transferId?: string;
  transferAccountId?: string;
  transferDirection?: string;
  balanceImpactMinor?: number;
  updatedAt: string;
};

export type TransactionFrequency = "weekly" | "everyTwoWeeks" | "monthly" | "yearly" | "everyTwoYears";

export type RecurringPayment = {
  id: string;
  name: string;
  amountMinor: number;
  currency: string;
  frequency: TransactionFrequency;
  nextDate: string;
  accountId?: string;
  category: string;
  isActive: boolean;
  scheduleAnchorDay?: number;
};

export type StockHolding = {
  id: string;
  symbol: string;
  name: string;
  quantity: number;
  averageCostMinor: number;
  currentPriceMinor: number;
  currency: string;
  linkedAccountId?: string;
  updatedAt: string;
};

export type StockTrade = {
  id: string;
  holdingId: string;
  symbol: string;
  side: "buy" | "sell";
  quantity: number;
  priceMinor: number;
  feesMinor: number;
  currency: string;
  tradedAt: string;
  linkedAccountId?: string;
};

export type SyncEntity = "account" | "transaction" | "recurringPayment" | "stockHolding" | "stockTrade";

export type SyncChange = {
  sequence: number;
  entity: SyncEntity;
  entityId: string;
  action: "upsert" | "delete";
  value: Record<string, unknown> | null;
};

export type SyncResponse = {
  cursor: string;
  changes: SyncChange[];
  acceptedMutationIds: string[];
};

export type SyncOperation = {
  mutationId: string;
  entity: SyncEntity;
  action: "upsert" | "delete";
  entityId: string;
  value: Record<string, unknown> | null;
  baseVersion: number;
};

export const accountKinds: { kind: AccountKind; label: string }[] = [
  { kind: "checking", label: "Checking" },
  { kind: "savings", label: "Savings" },
  { kind: "credit", label: "Credit card" },
  { kind: "sharedCredit", label: "Someone else's card" },
  { kind: "investment", label: "Investment" },
  { kind: "cash", label: "Cash" },
];

export const frequencies: { value: TransactionFrequency; label: string }[] = [
  { value: "weekly", label: "Weekly" },
  { value: "everyTwoWeeks", label: "Every 2 weeks" },
  { value: "monthly", label: "Monthly" },
  { value: "yearly", label: "Yearly" },
  { value: "everyTwoYears", label: "Every 2 years" },
];

export const transactionCategories = [
  "Bills",
  "Dining",
  "Groceries",
  "Shopping",
  "Transport",
  "Housing",
  "School",
  "Health",
  "Travel",
  "Subscriptions",
  "Deposit",
  "Refund",
  "Transfer",
];

export const quickSpendCategories = [
  "Dining",
  "Groceries",
  "Transport",
  "Shopping",
  "Bills",
  "Subscriptions",
  "Health",
  "School",
  "Travel",
  "Housing",
  "Other",
];

export const accountKindLabel = (kind: string) => accountKinds.find((item) => item.kind === kind)?.label ?? kind;

export const frequencyLabel = (frequency: string) =>
  frequencies.find((item) => item.value === frequency)?.label ?? "Monthly";
