import { bigint, boolean, index, integer, jsonb, pgEnum, pgTable, text, timestamp, uniqueIndex, uuid } from "drizzle-orm/pg-core";

export const accountKind = pgEnum("account_kind", ["checking", "savings", "credit", "investment", "cash"]);
export const runState = pgEnum("run_state", ["running", "succeeded", "failed"]);

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  externalId: text("external_id").notNull().unique(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const bankConnections = pgTable("bank_connections", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  provider: text("provider").notNull(),
  providerItemId: text("provider_item_id").notNull(),
  encryptedCredential: text("encrypted_credential"),
  status: text("status").notNull().default("healthy"),
  lastSuccessAt: timestamp("last_success_at", { withTimezone: true }),
  lastError: text("last_error"),
  nextCheckAt: timestamp("next_check_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [uniqueIndex("connection_provider_item").on(table.provider, table.providerItemId)]);

export const accounts = pgTable("accounts", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  connectionId: uuid("connection_id").references(() => bankConnections.id, { onDelete: "set null" }),
  providerAccountId: text("provider_account_id"),
  name: text("name").notNull(),
  institution: text("institution").notNull(),
  kind: accountKind("kind").notNull(),
  balanceMinor: bigint("balance_minor", { mode: "number" }).notNull(),
  currency: text("currency").notNull(),
  version: integer("version").notNull().default(1),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [uniqueIndex("provider_account").on(table.connectionId, table.providerAccountId)]);

export const transactions = pgTable("transactions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  accountId: uuid("account_id").notNull().references(() => accounts.id, { onDelete: "cascade" }),
  providerTransactionId: text("provider_transaction_id"),
  description: text("description").notNull(),
  amountMinor: bigint("amount_minor", { mode: "number" }).notNull(),
  currency: text("currency").notNull(),
  bookedAt: timestamp("booked_at", { withTimezone: true }).notNull(),
  pending: boolean("pending").notNull().default(false),
  category: text("category"),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
  version: integer("version").notNull().default(1),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [
  uniqueIndex("provider_transaction").on(table.accountId, table.providerTransactionId),
  index("transactions_user_booked").on(table.userId, table.bookedAt),
]);

export const syncChanges = pgTable("sync_changes", {
  sequence: bigint("sequence", { mode: "number" }).primaryKey().generatedAlwaysAsIdentity(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  entity: text("entity").notNull(),
  entityId: uuid("entity_id").notNull(),
  action: text("action").notNull(),
  value: jsonb("value"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
}, (table) => [index("sync_user_sequence").on(table.userId, table.sequence)]);

export const processedMutations = pgTable("processed_mutations", {
  mutationId: uuid("mutation_id").primaryKey(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  processedAt: timestamp("processed_at", { withTimezone: true }).notNull().defaultNow(),
});

export const automationRuns = pgTable("automation_runs", {
  id: uuid("id").primaryKey().defaultRandom(),
  connectionId: uuid("connection_id").notNull().references(() => bankConnections.id, { onDelete: "cascade" }),
  state: runState("state").notNull().default("running"),
  startedAt: timestamp("started_at", { withTimezone: true }).notNull().defaultNow(),
  finishedAt: timestamp("finished_at", { withTimezone: true }),
  errorCode: text("error_code"),
  diagnostics: jsonb("diagnostics"),
});
