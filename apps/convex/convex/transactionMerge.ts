type TransactionValue = Record<string, unknown>;

export function mergeTransactionValue(
  existing: TransactionValue,
  incoming: TransactionValue,
  actor: "user" | "automation",
  updatedAt: string,
): TransactionValue {
  const next = { ...incoming };
  const categoryWasUserEdited = existing.categoryUserEdited === true;

  if (actor === "automation") {
    delete next.categoryUserEdited;
    if (categoryWasUserEdited) delete next.category;
  }

  const categoryChangedByUser = actor === "user"
    && Object.hasOwn(next, "category")
    && next.category !== existing.category;

  return {
    ...existing,
    ...next,
    categoryUserEdited: categoryWasUserEdited || categoryChangedByUser || next.categoryUserEdited === true,
    updatedAt,
  };
}
