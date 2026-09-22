import type { Account, Transaction } from "@ledgerly/contracts";
import { StatusBar } from "expo-status-bar";
import { useCallback, useEffect, useMemo, useState } from "react";
import { RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { syncNow } from "../src/api";
import { cachedAccounts, cachedTransactions } from "../src/db";

const money = (minor: number, currency: string) => new Intl.NumberFormat(undefined, { style: "currency", currency }).format(minor / 100);

export default function Home() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const [offline, setOffline] = useState(false);
  const reload = useCallback(() => { setAccounts(cachedAccounts()); setTransactions(cachedTransactions()); }, []);
  const refresh = useCallback(async () => {
    setRefreshing(true);
    try { await syncNow(); setOffline(false); } catch { setOffline(true); } finally { reload(); setRefreshing(false); }
  }, [reload]);
  useEffect(() => { reload(); void refresh(); }, [refresh, reload]);
  const netWorth = useMemo(() => accounts.reduce((sum, account) => sum + account.balance.amountMinor, 0), [accounts]);

  return <SafeAreaView style={styles.safe}>
    <StatusBar style="light" />
    <ScrollView contentContainerStyle={styles.content} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={refresh} tintColor="#fff" />}>
      <View style={styles.heading}><Text style={styles.eyebrow}>OVERVIEW</Text><Text style={styles.title}>Good morning</Text></View>
      {offline && <Text style={styles.offline}>Offline · showing saved data</Text>}
      <View style={styles.hero}><Text style={styles.heroLabel}>TOTAL BALANCE</Text><Text style={styles.heroValue}>{money(netWorth, accounts[0]?.balance.currency ?? "USD")}</Text><Text style={styles.heroHint}>{accounts.length} connected account{accounts.length === 1 ? "" : "s"}</Text></View>
      <Text style={styles.section}>Accounts</Text>
      {accounts.map((account) => <View key={account.id} style={styles.card}><View><Text style={styles.cardTitle}>{account.name}</Text><Text style={styles.muted}>{account.institution}</Text></View><Text style={styles.amount}>{money(account.balance.amountMinor, account.balance.currency)}</Text></View>)}
      <Text style={styles.section}>Recent activity</Text>
      {transactions.slice(0, 8).map((item) => <View key={item.id} style={styles.row}><View style={styles.badge}><Text style={styles.badgeText}>{item.description[0]}</Text></View><View style={styles.grow}><Text style={styles.cardTitle}>{item.description}</Text><Text style={styles.muted}>{item.category ?? "Uncategorized"}</Text></View><Text style={[styles.amount, item.amount.amountMinor > 0 && styles.positive]}>{money(item.amount.amountMinor, item.amount.currency)}</Text></View>)}
      {!accounts.length && <Text style={styles.empty}>Pull to sync after running the demo bank automation.</Text>}
    </ScrollView>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#071712" }, content: { padding: 20, paddingBottom: 48, gap: 12 },
  heading: { marginTop: 16, marginBottom: 14 }, eyebrow: { color: "#70D6AD", letterSpacing: 2, fontWeight: "700", fontSize: 12 }, title: { color: "#F4FFF9", fontSize: 34, fontWeight: "700", marginTop: 5 },
  offline: { color: "#FFD28A" }, hero: { backgroundColor: "#123E31", borderRadius: 28, padding: 24, marginBottom: 12 }, heroLabel: { color: "#93CBB4", fontSize: 12, letterSpacing: 1.4 }, heroValue: { color: "white", fontSize: 40, fontWeight: "700", marginVertical: 9 }, heroHint: { color: "#A8D7C4" },
  section: { color: "#E9FFF6", fontSize: 20, fontWeight: "700", marginTop: 14, marginBottom: 2 }, card: { backgroundColor: "#10241D", borderRadius: 18, padding: 18, flexDirection: "row", justifyContent: "space-between", alignItems: "center" }, cardTitle: { color: "#F2FFF9", fontSize: 16, fontWeight: "600" }, muted: { color: "#7D9B8F", marginTop: 4 }, amount: { color: "#F2FFF9", fontWeight: "600" }, positive: { color: "#70D6AD" },
  row: { paddingVertical: 10, flexDirection: "row", alignItems: "center", gap: 12 }, badge: { width: 42, height: 42, borderRadius: 15, backgroundColor: "#18382D", alignItems: "center", justifyContent: "center" }, badgeText: { color: "#70D6AD", fontWeight: "700" }, grow: { flex: 1 }, empty: { color: "#7D9B8F", textAlign: "center", marginTop: 30 },
});
