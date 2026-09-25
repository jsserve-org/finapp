import type { Transaction } from "@ledgerly/contracts";
import { Ionicons } from "@expo/vector-icons";
import { useEffect, useState } from "react";
import { Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { cachedRecurringPayments, cachedTransactions, createRecurringPayment, type RecurringPayment } from "../src/db";

const money = (minor: number, currency: string) => new Intl.NumberFormat(undefined, { style: "currency", currency }).format(minor / 100);
const frequencyLabel: Record<RecurringPayment["frequency"], string> = { weekly: "Weekly", everyTwoWeeks: "Every 2 weeks", monthly: "Monthly", yearly: "Yearly", everyTwoYears: "Every 2 years" };
const frequencies: RecurringPayment["frequency"][] = ["weekly", "everyTwoWeeks", "monthly", "yearly", "everyTwoYears"];

export default function Activity() {
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [recurring, setRecurring] = useState<RecurringPayment[]>([]);
  const [showingNew, setShowingNew] = useState(false);
  const [name, setName] = useState("");
  const [amount, setAmount] = useState("");
  const [nextDate, setNextDate] = useState(new Date().toISOString().slice(0, 10));
  const [frequency, setFrequency] = useState<RecurringPayment["frequency"]>("monthly");
  const reload = () => { setTransactions(cachedTransactions()); setRecurring(cachedRecurringPayments()); };
  useEffect(reload, []);

  const save = () => {
    const amountMinor = Math.round((Number(amount) || 0) * 100);
    if (!name.trim() || amountMinor <= 0 || Number.isNaN(Date.parse(nextDate))) return;
    createRecurringPayment({ name: name.trim(), amountMinor, currency: "USD", frequency, nextDate: new Date(nextDate).toISOString(), category: "Bills" });
    reload(); setShowingNew(false); setName(""); setAmount(""); setFrequency("monthly");
  };

  return <SafeAreaView style={styles.safe}>
    <ScrollView contentContainerStyle={styles.content}>
      <Text style={styles.title}>Activity</Text>
      <View style={styles.sectionHeader}><Text style={styles.sectionTitle}>Recurring payments</Text><Pressable onPress={() => setShowingNew(true)}><Text style={styles.add}>＋ Add</Text></Pressable></View>
      {!recurring.length && <Pressable style={styles.recurringCard} onPress={() => setShowingNew(true)}><View style={styles.calendarIcon}><Ionicons name="calendar" color="#9CB7FF" size={24} /></View><View style={styles.grow}><Text style={styles.cardTitle}>Plan your regular bills</Text><Text style={styles.muted}>Add rent, subscriptions, or any repeating payment.</Text></View><Ionicons name="chevron-forward" color="#777E89" size={20} /></Pressable>}
      {recurring.map((item) => <View key={item.id} style={styles.recurringCard}><View style={styles.calendarIcon}><Ionicons name="repeat" color="#9CB7FF" size={22} /></View><View style={styles.grow}><Text style={styles.cardTitle}>{item.name}</Text><Text style={styles.muted}>{frequencyLabel[item.frequency]} · next {new Date(item.nextDate).toLocaleDateString()}</Text></View><Text style={styles.amount}>{money(-item.amountMinor, item.currency)}</Text></View>)}
      <Text style={[styles.sectionTitle, styles.transactionsTitle]}>Transactions</Text>
      {transactions.map((item) => <View key={item.id} style={styles.row}>
        <View style={styles.icon}><Ionicons name={item.amount.amountMinor > 0 ? "arrow-down" : "arrow-up"} color={item.amount.amountMinor > 0 ? "#9CB7FF" : "#FFD28A"} size={18} /></View>
        <View style={styles.grow}><Text style={styles.cardTitle}>{item.description}</Text><Text style={styles.muted}>{item.category ?? "Uncategorized"}</Text></View>
        <View><Text style={[styles.amount, item.amount.amountMinor > 0 && styles.positive]}>{money(item.amount.amountMinor, item.amount.currency)}</Text>{item.pending && <Text style={styles.pending}>Pending</Text>}</View>
      </View>)}
      {!transactions.length && <View style={styles.empty}><Ionicons name="receipt-outline" color="#9298A2" size={36} /><Text style={styles.cardTitle}>No activity yet</Text><Text style={styles.muted}>Transactions you add or sync will appear here.</Text></View>}
    </ScrollView>
    <Modal visible={showingNew} animationType="slide" presentationStyle="pageSheet"><SafeAreaView style={styles.modal}><View style={styles.modalHeader}><Pressable onPress={() => setShowingNew(false)}><Text style={styles.add}>Cancel</Text></Pressable><Text style={styles.modalTitle}>New recurring payment</Text><Pressable onPress={save}><Text style={styles.add}>Save</Text></Pressable></View><TextInput style={styles.input} value={name} onChangeText={setName} placeholder="Payment name" placeholderTextColor="#626873" /><TextInput style={styles.input} value={amount} onChangeText={setAmount} placeholder="Amount" placeholderTextColor="#626873" keyboardType="decimal-pad" /><TextInput style={styles.input} value={nextDate} onChangeText={setNextDate} placeholder="YYYY-MM-DD" placeholderTextColor="#626873" /><Text style={styles.fieldLabel}>Repeats</Text><View style={styles.frequencyRow}>{frequencies.map((value) => <Pressable key={value} style={[styles.frequency, frequency === value && styles.frequencySelected]} onPress={() => setFrequency(value)}><Text style={[styles.frequencyText, frequency === value && styles.frequencyTextSelected]}>{frequencyLabel[value]}</Text></Pressable>)}</View><Text style={styles.help}>Ledgerly tracks this schedule. It does not move money or charge your account.</Text></SafeAreaView></Modal>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#0B0C0F" }, content: { padding: 20, paddingBottom: 24 }, title: { color: "#F5F6F8", fontSize: 34, fontWeight: "700", marginTop: 18, marginBottom: 24 }, sectionHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 12 }, sectionTitle: { color: "#F5F6F8", fontSize: 22, fontWeight: "700" }, add: { color: "#9CB7FF", fontSize: 16, fontWeight: "700" }, recurringCard: { backgroundColor: "#17191F", borderRadius: 18, padding: 16, flexDirection: "row", alignItems: "center", gap: 12, marginBottom: 10 }, calendarIcon: { width: 46, height: 46, borderRadius: 15, backgroundColor: "#222630", alignItems: "center", justifyContent: "center" }, transactionsTitle: { marginTop: 24, marginBottom: 8 }, row: { paddingVertical: 13, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "#292D36", flexDirection: "row", alignItems: "center", gap: 12 }, icon: { width: 42, height: 42, borderRadius: 14, backgroundColor: "#222630", alignItems: "center", justifyContent: "center" }, grow: { flex: 1 }, cardTitle: { color: "#F5F6F8", fontSize: 17, fontWeight: "600" }, muted: { color: "#9298A2", fontSize: 15, lineHeight: 21, marginTop: 3 }, amount: { color: "#F5F6F8", fontSize: 16, fontWeight: "600", textAlign: "right" }, positive: { color: "#9CB7FF" }, pending: { color: "#FFD28A", fontSize: 13, textAlign: "right", marginTop: 3 }, empty: { alignItems: "center", gap: 10, paddingTop: 46 }, modal: { flex: 1, backgroundColor: "#0B0C0F", padding: 20, gap: 14 }, modalHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 14 }, modalTitle: { color: "#F5F6F8", fontSize: 17, fontWeight: "700" }, input: { backgroundColor: "#17191F", color: "#F5F6F8", fontSize: 17, padding: 16, borderRadius: 14 }, fieldLabel: { color: "#F5F6F8", fontSize: 17, fontWeight: "600", marginTop: 8 }, frequencyRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 }, frequency: { borderColor: "#353A46", borderWidth: 1, borderRadius: 12, paddingHorizontal: 12, paddingVertical: 10 }, frequencySelected: { backgroundColor: "#9CB7FF", borderColor: "#9CB7FF" }, frequencyText: { color: "#C9CDD4", fontSize: 15 }, frequencyTextSelected: { color: "#0B0C0F", fontWeight: "700" }, help: { color: "#9298A2", fontSize: 15, lineHeight: 21, marginTop: 8 },
});
