import { useLocalSearchParams } from "expo-router";
import { useMemo } from "react";
import { getCached } from "../../src/db";
import { BillForm } from "../../src/screens/BillForm";
import { EmptyState, Screen } from "../../src/components/List";
import { useCacheVersion } from "../../src/store";
import type { RecurringPayment } from "../../src/types";

export default function EditBillRoute() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const version = useCacheVersion();
  const payment = useMemo(() => getCached<RecurringPayment>("recurringPayment", id), [id, version]);
  if (!payment) {
    return (
      <Screen>
        <EmptyState icon="bill" title="Bill not found" message="It may have been deleted on another device." />
      </Screen>
    );
  }
  return <BillForm payment={payment} />;
}
