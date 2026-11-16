import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useMemo } from "react";
import { ScrollView, StyleSheet, Text } from "react-native";
import { cachedTransactionsNewest } from "../../../../src/db";
import { formatDate, formatMoney } from "../../../../src/format";
import { useCacheVersion } from "../../../../src/store";
import { useTheme } from "../../../../src/theme";
import { EmptyState, Row, Section, Screen } from "../../../../src/components/List";
import { paymentIconFor } from "../../../../src/components/Icon";

export default function CategoryScreen() {
  const { category, currency, month } = useLocalSearchParams<{ category: string; currency: string; month: string }>();
  const palette = useTheme();
  const router = useRouter();
  const version = useCacheVersion();
  const selectedMonth = month ? new Date(month) : new Date();

  const transactions = useMemo(
    () =>
      cachedTransactionsNewest(1000).filter((transaction) => {
        const date = new Date(transaction.bookedAt);
        return (
          transaction.amount.amountMinor < 0 &&
          transaction.amount.currency === currency &&
          (transaction.category ?? "Uncategorized") === category &&
          date.getFullYear() === selectedMonth.getFullYear() &&
          date.getMonth() === selectedMonth.getMonth()
        );
      }),
    [category, currency, selectedMonth, version],
  );

  const total = transactions.reduce((sum, transaction) => sum + Math.abs(transaction.amount.amountMinor), 0);

  return (
    <Screen>
      <Stack.Screen options={{ title: category ?? "Category" }} />
      <ScrollView contentContainerStyle={styles.content}>
        <Section title={selectedMonth.toLocaleDateString(undefined, { month: "long", year: "numeric" })}>
          <Row title="Spent" value={formatMoney(total, currency ?? "TWD")} valueColor={palette.red} />
          <Row title="Transactions" value={String(transactions.length)} />
        </Section>
        <Section title={`${transactions.length} transactions`}>
          {transactions.length === 0 ? (
            <EmptyState
              icon="calendar"
              title="No transactions"
              message={`No ${category ?? ""} expenses were recorded in this month.`}
            />
          ) : (
            transactions.map((transaction) => (
              <Row
                key={transaction.id}
                icon={paymentIconFor(transaction.description, transaction.category, transaction.amount.amountMinor)}
                iconColor={palette.red}
                title={transaction.description}
                subtitle={formatDate(transaction.bookedAt)}
                value={formatMoney(transaction.amount.amountMinor, transaction.amount.currency)}
                valueColor={palette.red}
                onPress={() =>
                  router.push({ pathname: "/insights/transaction/[id]", params: { id: transaction.id } } as never)
                }
              />
            ))
          )}
        </Section>
        <Text style={[styles.hint, { color: palette.secondaryLabel }]}>
          Only expenses booked between the first and last day of the selected month are included.
        </Text>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 22, paddingBottom: 60 },
  hint: { fontSize: 13, paddingHorizontal: 16 },
});
