import type { Account, Transaction } from "@ledgerly/contracts";
import { StatusBar } from "expo-status-bar";
import { Link, useFocusEffect } from "expo-router";
import { useCallback, useEffect, useMemo, useState } from "react";
import { RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { syncNow } from "../src/api";
import { cachedAccounts, cachedTransactions } from "../src/db";
import { useSession } from "../src/session";

const money = (minor: number, currency: string) => new Intl.NumberFormat(undefined, { style: "currency", currency }).format(minor / 100);

export default function Home() {
  const { token, localOnly } = useSession();
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [refreshing, setRefreshing] = useState(false);
  const [offline, setOffline] = useState(false);
  const reload = useCallback(() => { setAccounts(cachedAccounts()); setTransactions(cachedTransactions()); }, []);
  useFocusEffect(useCallback(() => { reload(); }, [reload]));
  const refresh = useCallback(async () => {
    setRefreshing(true);
    try { await syncNow(); setOffline(false); } catch { setOffline(true); } finally { reload(); setRefreshing(false); }
  }, [reload]);
  useEffect(() => { reload(); if (token) void refresh(); }, [refresh, reload, token]);
  const netWorth = useMemo(() => accounts.reduce((sum, account) => sum + account.balance.amountMinor, 0), [accounts]);

  return <SafeAreaView style={styles.safe}>
    <StatusBar style="light" />
    <ScrollView contentContainerStyle={styles.content} refreshControl={<RefreshControl refreshing={refreshing} onRefresh={token ? refresh : reload} tintColor="#fff" />}>
      <Text style={styles.title}>Overview</Text>
      <View style={styles.hero}><Text style={styles.heroLabel}>Net balance</Text><Text style={styles.heroValue}>{money(netWorth, accounts[0]?.balance.currency ?? "USD")}</Text><Text style={styles.heroHint}>{localOnly ? "Saved on this phone" : offline ? "Offline" : "Up to date"}</Text></View>
      <Text style={styles.section}>Accounts</Text>
      {accounts.map((account) => <View key={account.id} style={styles.card}><View><Text style={styles.cardTitle}>{account.name}</Text><Text style={styles.muted}>{account.institution}</Text></View><Text style={styles.amount}>{money(account.balance.amountMinor, account.balance.currency)}</Text></View>)}
      {!!transactions.length && <Text style={styles.section}>Recent activity</Text>}
      {transactions.slice(0, 8).map((item) => <View key={item.id} style={styles.row}><View style={styles.badge}><Text style={styles.badgeText}>{item.description[0]}</Text></View><View style={styles.grow}><Text style={styles.cardTitle}>{item.description}</Text><Text style={styles.muted}>{item.category ?? "Uncategorized"}</Text></View><Text style={[styles.amount, item.amount.amountMinor > 0 && styles.positive]}>{money(item.amount.amountMinor, item.amount.currency)}</Text></View>)}
      {!accounts.length && <View style={styles.emptyCard}><Text style={styles.emptyTitle}>Start with an account</Text><Text style={styles.empty}>Add a bank, card, cash, or savings account. It stays on this phone until you enable sync.</Text><Link href="/accounts" style={styles.link}>Create account</Link></View>}
    </ScrollView>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#0B0C0F" }, content: { padding: 20, paddingBottom: 24, gap: 12 }, title: { color: "#F5F6F8", fontSize: 34, fontWeight: "700", marginTop: 18, marginBottom: 10 },
  hero: { backgroundColor: "#17191F", borderRadius: 22, padding: 20, marginBottom: 12 }, heroLabel: { color: "#9298A2", fontSize: 16 }, heroValue: { color: "#F5F6F8", fontSize: 40, fontWeight: "700", marginVertical: 9 }, heroHint: { color: "#9298A2", fontSize: 15 },
  section: { color: "#F5F6F8", fontSize: 22, fontWeight: "700", marginTop: 14, marginBottom: 2 }, card: { backgroundColor: "#17191F", borderRadius: 18, padding: 18, flexDirection: "row", justifyContent: "space-between", alignItems: "center" }, cardTitle: { color: "#F5F6F8", fontSize: 17, fontWeight: "600" }, muted: { color: "#9298A2", fontSize: 15, marginTop: 4 }, amount: { color: "#F5F6F8", fontSize: 16, fontWeight: "600" }, positive: { color: "#9CB7FF" },
  row: { paddingVertical: 10, flexDirection: "row", alignItems: "center", gap: 12 }, badge: { width: 42, height: 42, borderRadius: 15, backgroundColor: "#222630", alignItems: "center", justifyContent: "center" }, badgeText: { color: "#9CB7FF", fontWeight: "700" }, grow: { flex: 1 }, emptyCard: { alignItems: "center", paddingVertical: 34, gap: 10 }, emptyTitle: { color: "#F5F6F8", fontSize: 18, fontWeight: "700" }, empty: { color: "#9298A2", textAlign: "center", maxWidth: 320 }, link: { color: "#9CB7FF", fontWeight: "700", marginTop: 8 },
});
