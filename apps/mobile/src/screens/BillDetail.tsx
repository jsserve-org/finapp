import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useMemo } from "react";
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { cachedAccounts, cachedRecurringPayments, cachedTransactions, getCached } from "../db";
import { formatDate, formatMoney } from "../format";
import { deleteRecurringPayment, saveRecurringPayment } from "../actions";
import { useCacheVersion, useHiddenAmounts } from "../store";
import { useTheme } from "../theme";
import { EmptyState, InfoRow, Row, Section, Screen } from "../components/List";
import { frequencyLabel, type RecurringPayment } from "../types";
import { warning } from "../haptics";

export default function BillDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const palette = useTheme();
  const router = useRouter();
  const version = useCacheVersion();
  const [hidden] = useHiddenAmounts();

  const payment = useMemo(() => getCached<RecurringPayment>("recurringPayment", id), [id, version]);
  const account = useMemo(
    () => cachedAccounts().find((item) => item.id === payment?.accountId),
    [payment, version],
  );
  const transactions = useMemo(
    () =>
      cachedTransactions()
        .filter((transaction) => transaction.recurringPaymentId === id)
        .sort((a, b) => b.bookedAt.localeCompare(a.bookedAt)),
    [id, version],
  );

  if (!payment) {
    return (
      <Screen>
        <Stack.Screen options={{ title: "Recurring bill" }} />
        <EmptyState icon="bill" title="Bill not found" message="It may have been deleted on another device." />
      </Screen>
    );
  }

  const shown = (amount: number, currency: string) => (hidden ? "••••" : formatMoney(amount, currency));

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: payment.name,
          headerRight: () => (
            <Pressable onPress={() => router.push({ pathname: "/bill/[id]", params: { id: payment.id } } as never)} hitSlop={10}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>Edit</Text>
            </Pressable>
          ),
        }}
      />
      <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content}>
        <Section
          title="Subscription"
          footer="Due dates create pending expense records. A matching recorded payment replaces the estimate. Pending records do not change your account balance."
        >
          <InfoRow label="Amount" value={formatMoney(payment.amountMinor, payment.currency)} />
          <InfoRow label="Status" value={payment.isActive ? "Active" : "Paused"} />
          <InfoRow label="Repeats" value={frequencyLabel(payment.frequency)} />
          <InfoRow label="Next record" value={formatDate(payment.nextDate)} />
          <InfoRow label="Category" value={payment.category} />
          <InfoRow label="Pay from" value={account?.name ?? "Choose an account to enable automatic records"} />
        </Section>

        <Section title={`All transactions (${transactions.length})`}>
          {transactions.length === 0 ? (
            <EmptyState icon="activity" title="No transactions linked yet" message="Payments that match this bill are linked automatically." />
          ) : (
            transactions.map((transaction) => (
              <Row
                key={transaction.id}
                icon="bill"
                title={transaction.description}
                subtitle={`${formatDate(transaction.bookedAt, "short")}${transaction.source === "subscription" && transaction.pending ? " · Expected payment" : ""}`}
                value={shown(transaction.amount.amountMinor, transaction.amount.currency)}
                valueColor={palette.label}
                strongValue
                onPress={() =>
                  router.push({ pathname: "/activity/transaction/[id]", params: { id: transaction.id } } as never)
                }
              />
            ))
          )}
        </Section>

        <Section>
          <Row
            icon={payment.isActive ? "minusCircle" : "checkCircle"}
            iconColor={payment.isActive ? palette.blue : palette.green}
            title={payment.isActive ? "Pause bill" : "Resume bill"}
            showChevron={false}
            onPress={() => {
            saveRecurringPayment({
              id: payment.id,
              name: payment.name,
              amountMinor: payment.amountMinor,
              currency: payment.currency,
              frequency: payment.frequency,
              nextDate: new Date(payment.nextDate),
              accountId: payment.accountId,
              category: payment.category,
              isActive: !payment.isActive,
            });
          }}
          />
          <Row
            icon="trash"
            iconColor={palette.red}
            title="Delete recurring bill"
            destructive
            showChevron={false}
            onPress={() =>
              Alert.alert("Delete recurring bill?", "Linked payments stay in Activity; pending estimates are removed.", [
                { text: "Cancel", style: "cancel" },
                {
                  text: "Delete",
                  style: "destructive",
                  onPress: () => {
                    deleteRecurringPayment(payment.id);
                    warning();
                    router.back();
                  },
                },
              ])
            }
          />
        </Section>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 18, paddingBottom: 40 },
});
