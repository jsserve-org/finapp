import type { Account } from "@ledgerly/contracts";
import { Ionicons } from "@expo/vector-icons";
import { useEffect, useMemo, useState } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { cachedAccounts } from "../src/db";

const money = (minor: number, currency: string) => new Intl.NumberFormat(undefined, { style: "currency", currency }).format(minor / 100);

export default function Accounts() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  useEffect(() => setAccounts(cachedAccounts()), []);
  const total = useMemo(() => accounts.reduce((sum, account) => sum + account.balance.amountMinor, 0), [accounts]);

  return <SafeAreaView style={styles.safe}>
    <ScrollView contentContainerStyle={styles.content}>
      <Text style={styles.title}>Accounts</Text>
      <Text style={styles.eyebrow}>ALL ACCOUNTS</Text>
      <Text style={styles.total}>{money(total, accounts[0]?.balance.currency ?? "USD")}</Text>
      <Text style={styles.muted}>Across {accounts.length} connected account{accounts.length === 1 ? "" : "s"}</Text>
      {accounts.map((account) => <View key={account.id} style={styles.card}>
        <View style={styles.icon}><Ionicons name="business" color="#70D6AD" size={21} /></View>
        <View style={styles.grow}><Text style={styles.cardTitle}>{account.name}</Text><Text style={styles.muted}>{account.institution} · {account.kind}</Text></View>
        <Text style={styles.amount}>{money(account.balance.amountMinor, account.balance.currency)}</Text>
      </View>)}
      {!accounts.length && <View style={styles.empty}><Ionicons name="business-outline" color="#70D6AD" size={34} /><Text style={styles.cardTitle}>No accounts yet</Text><Text style={styles.muted}>Sync from Overview to load your accounts.</Text></View>}
    </ScrollView>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#071712" }, content: { padding: 20, paddingBottom: 24, gap: 14 },
  title: { color: "#F4FFF9", fontSize: 22, fontWeight: "700", textAlign: "center", marginBottom: 16 }, eyebrow: { color: "#70D6AD", fontSize: 12, fontWeight: "700", letterSpacing: 2 }, total: { color: "#F4FFF9", fontSize: 38, fontWeight: "700" }, muted: { color: "#7D9B8F", marginTop: 3 },
  card: { backgroundColor: "#10241D", borderRadius: 20, padding: 16, flexDirection: "row", alignItems: "center", gap: 12 }, icon: { width: 46, height: 46, borderRadius: 15, backgroundColor: "#18382D", alignItems: "center", justifyContent: "center" }, grow: { flex: 1 }, cardTitle: { color: "#F2FFF9", fontSize: 16, fontWeight: "600" }, amount: { color: "#F2FFF9", fontWeight: "600" }, empty: { alignItems: "center", gap: 10, paddingTop: 64 },
});
