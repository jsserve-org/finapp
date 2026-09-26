import { describe, expect, test } from "bun:test";
import { mergeTransactionValue } from "../../convex/convex/transactionMerge";

describe("transaction user overrides", () => {
  test("a user category change becomes protected", () => {
    const result = mergeTransactionValue(
      { id: "t1", category: "Shopping", categoryUserEdited: false },
      { category: "Transfer" },
      "user",
      "2026-09-26T00:00:00.000Z",
    );
    expect(result.category).toBe("Transfer");
    expect(result.categoryUserEdited).toBe(true);
  });

  test("the app can explicitly protect a category even when its text is unchanged", () => {
    const result = mergeTransactionValue(
      { id: "t1", category: "Transfer", categoryUserEdited: false },
      { category: "Transfer", categoryUserEdited: true },
      "user",
      "2026-09-26T00:00:00.000Z",
    );
    expect(result.categoryUserEdited).toBe(true);
  });

  test("automation updates bank data without replacing a protected category", () => {
    const result = mergeTransactionValue(
      { id: "t1", category: "Transfer", categoryUserEdited: true, pending: true },
      { category: "Shopping", pending: false, description: "Imported bank memo" },
      "automation",
      "2026-09-26T00:00:00.000Z",
    );
    expect(result.category).toBe("Transfer");
    expect(result.categoryUserEdited).toBe(true);
    expect(result.pending).toBe(false);
    expect(result.description).toBe("Imported bank memo");
  });

  test("automation can categorize a transaction the user has not categorized", () => {
    const result = mergeTransactionValue(
      { id: "t1", pending: false },
      { category: "Fees", categoryUserEdited: true },
      "automation",
      "2026-09-26T00:00:00.000Z",
    );
    expect(result.category).toBe("Fees");
    expect(result.categoryUserEdited).toBe(false);
  });
});
