import type { Account, Transaction } from "@ledgerly/contracts";
import { useFocusEffect, useRouter } from "expo-router";
import { useCallback, useRef, useState } from "react";
import { RefreshControl, StyleSheet, View } from "react-native";
import { Appbar, Button, Card, Divider, List, Menu, Text, useTheme } from "react-native-paper";
import { syncNow } from "../../src/api";
import { cachedAccounts, cachedHoldings, cachedTransactions } from "../../src/db";
import { insights, monthKey, monthLabel, type Holding } from "../../src/finance";
import { useSession } from "../../src/session";
import { RowIcon, Screen, useAmounts, useMoneyColors } from "../../src/ui";

export default function Insights() {
  const theme = useTheme();
  const colors = useMoneyColors();
  const { money, hidden, toggle } = useAmounts();
  const { token } = useSession();
  const router = useRouter();
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [holdings, setHoldings] = useState<Holding[]>([]);
  const [month, setMonth] = useState(() => monthKey(new Date()));
  const [choosingMonth, setChoosingMonth] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const syncInFlight = useRef(false);
  const [error, setError] = useState<string>();
  const reload = useCallback(() => { setAccounts(cachedAccounts()); setTransactions(cachedTransactions()); setHoldings(cachedHoldings()); }, []);
  const refresh = useCallback(async () => {
    if (syncInFlight.current) return;
    syncInFlight.current = true;
    setRefreshing(true); setError(undefined);
    try { if (token) await syncNow(); } catch (error) { setError(error instanceof Error ? error.message : "Sync failed"); }
    finally { syncInFlight.current = false; reload(); setRefreshing(false); }
  }, [token, reload]);
  useFocusEffect(useCallback(() => { reload(); if (token) void refresh(); }, [reload, token, refresh]));
  const summary = insights(accounts, transactions, holdings, month);

  return <Screen title="Insights" actions={<Appbar.Action icon={hidden ? "eye-off-outline" : "eye-outline"} accessibilityLabel={hidden ? "Show financial amounts" : "Hide financial amounts"} onPress={toggle} />}
    refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void refresh()} colors={[theme.colors.primary]} tintColor={theme.colors.primary} />}>
    {error && <Text style={{ color: theme.colors.error }}>{error}</Text>}
    <View style={styles.group}>
      <Text variant="titleMedium" style={styles.heading}>Summary</Text>
      <Card mode="contained">
        {!summary.totals.length && <><List.Item title="No insights yet" description="Add an account or transaction to see your financial summary." descriptionNumberOfLines={3} left={props => <RowIcon style={props.style} icon="chart-bar" />} /><Card.Actions><Button onPress={() => router.push("/accounts?create=1")}>Add an account</Button></Card.Actions></>}
        {summary.totals.map((total, index) => <View key={total.currency}>
          {index > 0 && <Divider />}
          <Card.Content style={styles.currencySummary}>
            <Text variant="labelLarge" style={{ color: theme.colors.onSurfaceVariant }}>{total.currency}</Text>
            <View style={styles.line}><Text>Net worth</Text><Text variant="headlineSmall" numberOfLines={1} adjustsFontSizeToFit style={styles.value}>{money(total.balance, total.currency)}</Text></View>
            <View style={styles.line}><Text>Money in</Text><Text variant="titleMedium" style={{ color: colors.income }}>{money(total.income, total.currency)}</Text></View>
            <View style={styles.line}><Text>Money out</Text><Text variant="titleMedium" style={{ color: colors.expense }}>{money(total.spending, total.currency)}</Text></View>
          </Card.Content>
        </View>)}
      </Card>
    </View>
    <View style={styles.group}>
      <View style={styles.sectionHeader}>
        <Text variant="titleMedium">Spending by category</Text>
        <Menu visible={choosingMonth} onDismiss={() => setChoosingMonth(false)} anchor={<Button compact icon="calendar-blank-outline" onPress={() => setChoosingMonth(true)}>{monthLabel(month)}</Button>}>
          {summary.months.map(value => <Menu.Item key={value} title={monthLabel(value)} leadingIcon={month === value ? "check" : undefined} onPress={() => { setMonth(value); setChoosingMonth(false); }} />)}
        </Menu>
      </View>
      <Card mode="contained">
        {summary.categories.map((category, index) => <View key={`${category.currency}-${category.category}`}>
          {index > 0 && <Divider />}
          <List.Item title={category.category} left={props => <List.Icon {...props} icon="tag-outline" />} right={() => <Text variant="titleSmall" style={styles.amount}>{money(category.amount, category.currency)}</Text>} />
        </View>)}
        {!summary.categories.length && <List.Item title="No spending this month" description="Choose another month to see its expenses." left={props => <List.Icon {...props} icon="calendar-blank-outline" />} />}
      </Card>
    </View>
    <View style={styles.group}>
      <Text variant="titleMedium" style={styles.heading}>Investments</Text>
      <Card mode="contained">
        <List.Item title="Portfolio" description={!holdings.length ? "Holdings appear here once your investment automation syncs." : `${holdings.length} synced positions`} descriptionNumberOfLines={3} left={props => <RowIcon style={props.style} icon="chart-line" />} />
        {summary.portfolio.map(([currency, value]) => <List.Item key={currency} title={currency} right={() => <Text variant="titleMedium" style={styles.amount}>{money(value, currency)}</Text>} />)}
      </Card>
    </View>
  </Screen>;
}
const styles = StyleSheet.create({ group: { gap: 8 }, heading: { marginLeft: 4 }, sectionHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap" }, currencySummary: { gap: 14, paddingVertical: 16 }, line: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12 }, value: { flexShrink: 1, textAlign: "right" }, amount: { alignSelf: "center" } });
