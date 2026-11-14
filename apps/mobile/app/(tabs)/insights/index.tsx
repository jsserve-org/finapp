import { Stack, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { ActionSheetIOS, Platform } from "react-native";
import { cachedAccounts, cachedHoldings, cachedTransactionsNewest } from "../../../src/db";
import { formatMoney, formatMonthShort, addMonths, startOfMonth } from "../../../src/format";
import { availableMonths, categoryTotals, flowsForCurrency, netWorthByCurrency, portfolioTotals } from "../../../src/insights";
import { useCacheVersion, useHiddenAmounts } from "../../../src/store";
import { useSession } from "../../../src/session";
import { useSync } from "../../../src/sync";
import { useTheme } from "../../../src/theme";
import { GlassSurface } from "../../../src/components/Glass";
import { EmptyState, Row, Section, Screen } from "../../../src/components/List";
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
      accounts,
      transactions,
      holdings,
      currencies,
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
    const current = data.months.findIndex((month) => month.getMonth() === selectedMonth.getMonth() && month.getFullYear() === selectedMonth.getFullYear());
    setSelectedMonth(data.months[(current + 1) % data.months.length] ?? startOfMonth(new Date()));
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
          <View style={[styles.errorCard, { backgroundColor: palette.card }]}>
            <Icon name="warning" size={17} color={palette.red} />
            <View style={{ flex: 1, gap: 2 }}>
              <Text style={{ color: palette.red, fontSize: 15, fontWeight: "600" }}>{lastError}</Text>
              <Text style={{ color: palette.secondaryLabel, fontSize: 13 }}>Open Settings → Server after updating the app or backend.</Text>
            </View>
          </View>
        ) : null}

        {data.currencies.length === 0 ? (
          <Section title="Summary">
            <EmptyState
              icon="insights"
              title="No insights yet"
              message="Add an account or transaction to start seeing your financial summary."
            />
          </Section>
        ) : (
          data.currencies.map((currency) => {
            const { inflow, outflow } = flowsForCurrency(data.transactions, currency);
            const netWorth = data.netWorth.find((item) => item.currency === currency)?.amount ?? 0;
            return (
              <GlassSurface key={currency} style={styles.hero}>
                <Text style={[styles.heroCurrency, { color: palette.secondaryLabel }]}>{currency}</Text>
                <Text style={[styles.heroValue, { color: palette.label }]}>{shown(netWorth, currency)}</Text>
                <Text style={[styles.heroLabel, { color: palette.secondaryLabel }]}>Net worth</Text>
                <View style={styles.heroFlows}>
                  <View style={styles.heroFlow}>
                    <Text style={[styles.flowLabel, { color: palette.secondaryLabel }]}>Money in</Text>
                    <Text style={[styles.flowValue, { color: palette.green }]}>{shown(inflow, currency)}</Text>
                  </View>
                  <View style={[styles.flowDivider, { backgroundColor: palette.separator }]} />
                  <View style={styles.heroFlow}>
                    <Text style={[styles.flowLabel, { color: palette.secondaryLabel }]}>Money out</Text>
                    <Text style={[styles.flowValue, { color: palette.red }]}>{shown(outflow, currency)}</Text>
                  </View>
                </View>
              </GlassSurface>
            );
          })
        )}

        <Section
          title="Spending by category"
          headerAccessory={
            <Pressable onPress={pickMonth} style={styles.monthButton}>
              <Icon name="calendar" size={12} color={palette.blue} />
              <Text style={{ color: palette.blue, fontSize: 13, fontWeight: "600" }}>{formatMonthShort(selectedMonth)}</Text>
            </Pressable>
          }
        >
          {data.categories.length === 0 ? (
            <EmptyState icon="pieChart" title="No spending this month" message="Choose another month or add an expense." />
          ) : (
            data.categories.map((item) => (
              <Row
                key={`${item.currency}|${item.category}`}
                icon={paymentIconFor("", item.category, -1)}
                title={item.category}
                value={shown(item.amount, item.currency)}
                valueColor={palette.label}
                onPress={() =>
                  router.push({
                    pathname: "/insights/category/[category]",
                    params: {
                      category: item.category,
                      currency: item.currency,
                      month: selectedMonth.toISOString(),
                    },
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
            subtitle={data.holdings.length === 0 ? "Add your first stock trade" : `${data.holdings.length} holdings`}
            onPress={() => router.push("/insights/portfolio" as never)}
          />
          {portfolioTotals(data.holdings).map((total) => (
            <Row key={total.currency} title={total.currency} value={shown(total.amount, total.currency)} valueColor={palette.label} />
          ))}
        </Section>
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
  content: { padding: 16, gap: 22, paddingBottom: 120 },
  hero: { padding: 20, gap: 4 },
  heroCurrency: { fontSize: 13, fontWeight: "600", letterSpacing: 0.6 },
  heroValue: { fontSize: 38, fontWeight: "700", fontVariant: ["tabular-nums"] },
  heroLabel: { fontSize: 13 },
  heroFlows: { flexDirection: "row", alignItems: "center", marginTop: 14, gap: 14 },
  heroFlow: { flex: 1, gap: 2 },
  flowLabel: { fontSize: 12 },
  flowValue: { fontSize: 17, fontWeight: "600", fontVariant: ["tabular-nums"] },
  flowDivider: { width: StyleSheet.hairlineWidth, height: 30 },
  monthButton: { flexDirection: "row", alignItems: "center", gap: 5 },
  errorCard: { flexDirection: "row", gap: 10, padding: 14, borderRadius: 16, alignItems: "flex-start" },
});
