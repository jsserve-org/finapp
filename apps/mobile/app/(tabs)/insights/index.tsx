import { Stack, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { ActionSheetIOS, Platform, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { cachedAccounts, cachedHoldings, cachedTransactionsNewest } from "../../../src/db";
import { formatMoney, formatMonthShort, startOfMonth } from "../../../src/format";
import { availableMonths, categoryTotals, flowsForCurrency, netWorthByCurrency, portfolioTotals } from "../../../src/insights";
import { useCacheVersion, useHiddenAmounts } from "../../../src/store";
import { useSession } from "../../../src/session";
import { useSync } from "../../../src/sync";
import { useTheme } from "../../../src/theme";
import { EmptyState, Row, Section, Screen, ValueRow } from "../../../src/components/List";
import { Icon, paymentIconFor } from "../../../src/components/Icon";

export default function InsightsScreen() {
  const palette = useTheme();
  const version = useCacheVersion();
  const { refresh, isSyncing, lastError } = useSync();
  const { token } = useSession();
  const [hidden] = useHiddenAmounts();
  const [selectedMonth, setSelectedMonth] = useState(() => startOfMonth(new Date()));
  const router = useRouter();

  const data = useMemo(() => {
    const accounts = cachedAccounts();
    const transactions = cachedTransactionsNewest(1000);
    const holdings = cachedHoldings();
    const currencies = [...new Set([...accounts.map((a) => a.balance.currency), ...transactions.map((t) => t.amount.currency), ...holdings.map((h) => h.currency)])].sort();
    return {
      currencies,
      transactions,
      holdings,
      netWorth: netWorthByCurrency(accounts, holdings),
      categories: categoryTotals(transactions, selectedMonth),
      months: availableMonths(transactions),
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version, selectedMonth]);

  const pickMonth = () => {
    const labels = data.months.map((month) => formatMonthShort(month));
    if (Platform.OS === "ios") {
      ActionSheetIOS.showActionSheetWithOptions(
        { options: ["Cancel", ...labels], cancelButtonIndex: 0, title: "Spending month" },
        (index) => {
          if (index > 0) setSelectedMonth(data.months[index - 1]);
        },
      );
      return;
    }
    const index = data.months.findIndex((month) => month.getMonth() === selectedMonth.getMonth() && month.getFullYear() === selectedMonth.getFullYear());
    setSelectedMonth(data.months[(index + 1) % Math.max(1, data.months.length)] ?? startOfMonth(new Date()));
  };

  const shown = (amount: number, currency: string) => (hidden ? "••••" : formatMoney(amount, currency));

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: "Insights",
          headerLargeTitle: true,
          headerRight: () => <VisibilityToggle />,
        }}
      />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl
            refreshing={isSyncing}
            onRefresh={() => void refresh()}
            tintColor={palette.secondaryLabel}
            enabled={token != null}
          />
        }
      >
        {lastError ? (
          <Section footer="Open Settings → Server after updating the app or backend.">
            <Row icon="warning" iconColor={palette.red} title={lastError} destructive />
          </Section>
        ) : null}

        <Section title="Summary">
          {data.currencies.length === 0 ? (
            <EmptyState
              icon="insights"
              title="No insights yet"
              message="Add an account or transaction to start seeing your financial summary."
            />
          ) : (
            data.currencies.map((currency) => {
              const { inflow, outflow } = flowsForCurrency(data.transactions, currency);
              const netWorth = data.netWorth.find((item) => item.currency === currency)?.amount ?? 0;
              return (
                <View key={currency} style={styles.summaryBlock}>
                  <Text style={[styles.currency, { color: palette.label }]}>{currency}</Text>
                  <ValueRow label="Net worth" value={shown(netWorth, currency)} emphasis />
                  <ValueRow label="Money in" value={shown(inflow, currency)} valueColor={palette.green} />
                  <ValueRow label="Money out" value={shown(outflow, currency)} valueColor={palette.red} />
                </View>
              );
            })
          )}
        </Section>

        <Section
          title="Spending by category"
          headerAccessory={
            <Pressable onPress={pickMonth} style={styles.monthButton} hitSlop={8}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>{formatMonthShort(selectedMonth)}</Text>
            </Pressable>
          }
        >
          {data.categories.length === 0 ? (
            <EmptyState icon="calendar" title="No spending this month" message="Choose another month to see its expenses." />
          ) : (
            data.categories.map((item) => (
              <Row
                key={`${item.currency}|${item.category}`}
                icon={paymentIconFor("", item.category, -1)}
                iconColor={palette.blue}
                title={item.category}
                value={shown(item.amount, item.currency)}
                valueColor={palette.label}
                onPress={() =>
                  router.push({
                    pathname: "/insights/category/[category]",
                    params: { category: item.category, currency: item.currency, month: selectedMonth.toISOString() },
                  } as never)
                }
              />
            ))
          )}
        </Section>

        <Section title="Investments">
          <Row
            icon="investment"
            title="Portfolio"
            subtitle={data.holdings.length === 0 ? "Add your first stock trade" : undefined}
            value={data.holdings.length === 0 ? undefined : shown(portfolioTotals(data.holdings)[0]?.amount ?? 0, portfolioTotals(data.holdings)[0]?.currency ?? "TWD")}
            valueColor={palette.label}
            onPress={() => router.push("/insights/portfolio" as never)}
          />
          {portfolioTotals(data.holdings)
            .slice(1)
            .map((total) => (
              <Row key={total.currency} title={total.currency} value={shown(total.amount, total.currency)} valueColor={palette.label} />
            ))}
        </Section>
        <View style={{ height: 28 }} />
      </ScrollView>
    </Screen>
  );
}

function VisibilityToggle() {
  const palette = useTheme();
  const [hidden, setHidden] = useHiddenAmounts();
  return (
    <Pressable
      onPress={() => setHidden(!hidden)}
      accessibilityLabel={hidden ? "Show financial amounts" : "Hide financial amounts"}
      hitSlop={10}
    >
      <Icon name={hidden ? "eyeSlash" : "eye"} size={19} color={palette.blue} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 0, gap: 22, paddingBottom: 120 },
  summaryBlock: { paddingVertical: 6 },
  currency: { fontSize: 17, fontWeight: "600", paddingHorizontal: 16, paddingTop: 6, paddingBottom: 2 },
  monthButton: { flexDirection: "row", alignItems: "center", gap: 5 },
});
