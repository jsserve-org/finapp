import type { Account } from "@ledgerly/contracts";
import { Ionicons } from "@expo/vector-icons";
import { useEffect, useMemo, useState } from "react";
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { cachedAccounts, createLocalAccount } from "../src/db";

const money = (minor: number, currency: string) => new Intl.NumberFormat(undefined, { style: "currency", currency }).format(minor / 100);

export default function Accounts() {
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [showingNew, setShowingNew] = useState(false); const [name, setName] = useState(""); const [balance, setBalance] = useState("");
  useEffect(() => setAccounts(cachedAccounts()), []);
  const total = useMemo(() => accounts.reduce((sum, account) => sum + account.balance.amountMinor, 0), [accounts]);

  return <SafeAreaView style={styles.safe}>
    <ScrollView contentContainerStyle={styles.content}>
      <View style={styles.header}><Text style={styles.title}>Accounts</Text><Pressable onPress={() => setShowingNew(true)}><Ionicons name="add-circle" color="#9CB7FF" size={30} /></Pressable></View>
      <Text style={styles.total}>{money(total, accounts[0]?.balance.currency ?? "USD")}</Text>
      <Text style={styles.muted}>Across {accounts.length} connected account{accounts.length === 1 ? "" : "s"}</Text>
      {accounts.map((account) => <View key={account.id} style={styles.card}>
        <View style={styles.icon}><Ionicons name="business" color="#9CB7FF" size={21} /></View>
        <View style={styles.grow}><Text style={styles.cardTitle}>{account.name}</Text><Text style={styles.muted}>{account.institution} · {account.kind}</Text></View>
        <Text style={styles.amount}>{money(account.balance.amountMinor, account.balance.currency)}</Text>
      </View>)}
      {!accounts.length && <View style={styles.empty}><Ionicons name="wallet-outline" color="#9298A2" size={34} /><Text style={styles.cardTitle}>Start with an account</Text><Text style={styles.muted}>Create one on this phone. Sync is optional.</Text><Pressable style={styles.button} onPress={() => setShowingNew(true)}><Text style={styles.buttonText}>Create account</Text></Pressable></View>}
    </ScrollView>
    <Modal visible={showingNew} animationType="slide" presentationStyle="pageSheet"><SafeAreaView style={styles.modal}><View style={styles.modalHeader}><Pressable onPress={() => setShowingNew(false)}><Text style={styles.link}>Cancel</Text></Pressable><Text style={styles.cardTitle}>New account</Text><Pressable disabled={!name.trim()} onPress={() => { createLocalAccount({ name: name.trim(), institution: "Manual", kind: "checking", amountMinor: Math.round((Number(balance) || 0) * 100), currency: "USD" }); setAccounts(cachedAccounts()); setShowingNew(false); setName(""); setBalance(""); }}><Text style={styles.link}>Save</Text></Pressable></View><TextInput style={styles.input} value={name} onChangeText={setName} placeholder="Account name" placeholderTextColor="#626873" /><TextInput style={styles.input} value={balance} onChangeText={setBalance} placeholder="Opening balance" placeholderTextColor="#626873" keyboardType="decimal-pad" /><Text style={styles.muted}>Saved locally. You can enable sync later.</Text></SafeAreaView></Modal>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#0B0C0F" }, content: { padding: 20, paddingBottom: 24, gap: 14 }, header: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 14 },
  title: { color: "#F5F6F8", fontSize: 34, fontWeight: "700" }, total: { color: "#F5F6F8", fontSize: 40, fontWeight: "700" }, muted: { color: "#9298A2", fontSize: 15, lineHeight: 21, marginTop: 3 },
  card: { backgroundColor: "#17191F", borderRadius: 18, padding: 16, flexDirection: "row", alignItems: "center", gap: 12 }, icon: { width: 46, height: 46, borderRadius: 15, backgroundColor: "#222630", alignItems: "center", justifyContent: "center" }, grow: { flex: 1 }, cardTitle: { color: "#F5F6F8", fontSize: 17, fontWeight: "600" }, amount: { color: "#F5F6F8", fontSize: 16, fontWeight: "600" }, empty: { alignItems: "center", gap: 10, paddingTop: 64 }, button: { backgroundColor: "#7A9FFF", borderRadius: 14, paddingHorizontal: 18, paddingVertical: 12, marginTop: 8 }, buttonText: { color: "#0B0C0F", fontSize: 16, fontWeight: "800" }, modal: { flex: 1, backgroundColor: "#0B0C0F", padding: 20, gap: 14 }, modalHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }, link: { color: "#9CB7FF", fontSize: 16, fontWeight: "600" }, input: { backgroundColor: "#17191F", color: "#F5F6F8", fontSize: 16, padding: 16, borderRadius: 14 },
});
