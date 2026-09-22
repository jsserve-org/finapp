import type { Account, Transaction } from "@ledgerly/contracts";
import { Ionicons } from "@expo/vector-icons";
import { useEffect, useMemo, useState } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { cachedAccounts, cachedTransactions } from "../src/db";

const money = (minor: number, currency: string) => new Intl.NumberFormat(undefined, { style: "currency", currency }).format(minor / 100);

export default function Insights() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  useEffect(() => { setAccounts(cachedAccounts()); setTransactions(cachedTransactions()); }, []);
  const values = useMemo(() => ({
    balance: accounts.reduce((sum, item) => sum + item.balance.amountMinor, 0),
    income: transactions.filter((item) => item.amount.amountMinor > 0).reduce((sum, item) => sum + item.amount.amountMinor, 0),
    spending: Math.abs(transactions.filter((item) => item.amount.amountMinor < 0).reduce((sum, item) => sum + item.amount.amountMinor, 0)),
  }), [accounts, transactions]);
  const currency = accounts[0]?.balance.currency ?? "USD";

  return <SafeAreaView style={styles.safe}><ScrollView contentContainerStyle={styles.content}>
    <Text style={styles.title}>Insights</Text><Text style={styles.eyebrow}>YOUR MONEY AT A GLANCE</Text>
    <Metric title="Net worth" value={money(values.balance, currency)} icon="analytics" />
    <View style={styles.row}><Metric title="Money in" value={money(values.income, currency)} icon="arrow-down-left" /><Metric title="Money out" value={money(values.spending, currency)} icon="arrow-up-right" /></View>
    <View style={styles.card}><Ionicons name="pie-chart" color="#70D6AD" size={24} /><Text style={styles.cardTitle}>Snapshot</Text><Text style={styles.muted}>{transactions.length ? `Based on ${transactions.length} saved transactions.` : "Your trends will appear after the first sync."}</Text></View>
  </ScrollView></SafeAreaView>;
}

function Metric({ title, value, icon }: { title: string; value: string; icon: "analytics" | "arrow-down-left" | "arrow-up-right" }) {
  return <View style={styles.metric}><Ionicons name={icon} color="#70D6AD" size={21} /><Text style={styles.muted}>{title}</Text><Text numberOfLines={1} adjustsFontSizeToFit style={styles.value}>{value}</Text></View>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#071712" }, content: { padding: 20, paddingBottom: 24, gap: 14 }, title: { color: "#F4FFF9", fontSize: 22, fontWeight: "700", textAlign: "center", marginBottom: 16 }, eyebrow: { color: "#70D6AD", fontSize: 12, fontWeight: "700", letterSpacing: 2 }, row: { flexDirection: "row", gap: 12 }, metric: { flex: 1, backgroundColor: "#10241D", borderRadius: 22, padding: 18, gap: 8 }, value: { color: "#F2FFF9", fontSize: 20, fontWeight: "700" }, card: { backgroundColor: "#10241D", borderRadius: 22, padding: 20, gap: 10 }, cardTitle: { color: "#F2FFF9", fontSize: 17, fontWeight: "600" }, muted: { color: "#7D9B8F" },
});
