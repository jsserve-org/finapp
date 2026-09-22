import type { Transaction } from "@ledgerly/contracts";
import { Ionicons } from "@expo/vector-icons";
import { useEffect, useState } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { cachedTransactions } from "../src/db";

const money = (minor: number, currency: string) => new Intl.NumberFormat(undefined, { style: "currency", currency }).format(minor / 100);

export default function Activity() {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  useEffect(() => setTransactions(cachedTransactions()), []);
  return <SafeAreaView style={styles.safe}><ScrollView contentContainerStyle={styles.content}>
    <Text style={styles.title}>Activity</Text>
    {transactions.map((item) => <View key={item.id} style={styles.row}>
      <View style={styles.icon}><Ionicons name={item.amount.amountMinor > 0 ? "arrow-down-left" : "arrow-up-right"} color={item.amount.amountMinor > 0 ? "#70D6AD" : "#FFD28A"} size={18} /></View>
      <View style={styles.grow}><Text style={styles.cardTitle}>{item.description}</Text><Text style={styles.muted}>{item.category ?? "Uncategorized"}</Text></View>
      <View><Text style={[styles.amount, item.amount.amountMinor > 0 && styles.positive]}>{money(item.amount.amountMinor, item.amount.currency)}</Text>{item.pending && <Text style={styles.pending}>Pending</Text>}</View>
    </View>)}
    {!transactions.length && <View style={styles.empty}><Ionicons name="receipt-outline" color="#70D6AD" size={34} /><Text style={styles.cardTitle}>No activity yet</Text><Text style={styles.muted}>Transactions will appear here after you sync.</Text></View>}
  </ScrollView></SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#071712" }, content: { padding: 20, paddingBottom: 24 }, title: { color: "#F4FFF9", fontSize: 22, fontWeight: "700", textAlign: "center", marginBottom: 20 }, row: { paddingVertical: 13, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "#244139", flexDirection: "row", alignItems: "center", gap: 12 }, icon: { width: 42, height: 42, borderRadius: 14, backgroundColor: "#18382D", alignItems: "center", justifyContent: "center" }, grow: { flex: 1 }, cardTitle: { color: "#F2FFF9", fontSize: 16, fontWeight: "600" }, muted: { color: "#7D9B8F", marginTop: 3 }, amount: { color: "#F2FFF9", fontWeight: "600", textAlign: "right" }, positive: { color: "#70D6AD" }, pending: { color: "#FFD28A", fontSize: 11, textAlign: "right", marginTop: 3 }, empty: { alignItems: "center", gap: 10, paddingTop: 64 },
});
