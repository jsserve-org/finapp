import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { cachedAccounts, cachedRecurringPayments, getCached } from "../db";
import { formatDate, formatMoney } from "../format";
import { deleteTransaction, updateTransaction } from "../actions";
import { transactionPresentation } from "../insights";
import { useCacheVersion } from "../store";
import { useTheme } from "../theme";
import { CategoryPicker, FormField } from "../components/Fields";
import { EmptyState, InfoRow, Row, Section, Screen } from "../components/List";
import { Icon, paymentIconFor } from "../components/Icon";
import { success, warning } from "../haptics";
import type { Transaction } from "../types";

export default function TransactionDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const palette = useTheme();
  const router = useRouter();
  const version = useCacheVersion();
  const [editing, setEditing] = useState(false);
  const [description, setDescription] = useState("");
  const [category, setCategory] = useState("");
  const [billPickerVisible, setBillPickerVisible] = useState(false);

  const transaction = useMemo(() => getCached<Transaction>("transaction", id), [id, version]);
  const account = useMemo(() => cachedAccounts().find((item) => item.id === transaction?.accountId), [transaction, version]);
  const bills = useMemo(() => cachedRecurringPayments(), [version]);
  const linkedBill = useMemo(() => bills.find((bill) => bill.id === transaction?.recurringPaymentId), [bills, transaction]);
  const transferAccount = useMemo(
    () => cachedAccounts().find((item) => item.id === transaction?.transferAccountId),
    [transaction, version],
  );

  if (!transaction) {
    return (
      <Screen>
        <Stack.Screen options={{ title: "Transaction" }} />
        <EmptyState icon="activity" title="Transaction not found" message={`It may have been deleted on another device. (${String(id)})`} />
      </Screen>
    );
  }

  const { amountMinor, currency, awaitingSettlement } = transactionPresentation(transaction);
  const tone = amountMinor >= 0 ? palette.green : palette.red;

  const startEditing = () => {
    setDescription(transaction.description);
    setCategory(transaction.category ?? "Uncategorized");
    setEditing(true);
  };

  const save = () => {
    updateTransaction(transaction.id, { description, category });
    setEditing(false);
    success();
  };

  const confirmDelete = () => {
    Alert.alert("Delete this transaction?", "The account balance will be adjusted to remove this transaction.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Delete",
        style: "destructive",
        onPress: () => {
          deleteTransaction(transaction.id);
          warning();
          router.back();
        },
      },
    ]);
  };

  const sourceLabel = (() => {
    switch (transaction.source) {
      case "manual":
        return "Added on this device";
      case "transfer":
        return "Transfer";
      case "screenshot":
        return "Screenshot import";
      case "refund":
        return "Refund";
      case "reimbursement":
        return "Reimbursement";
      case "bill":
      case "subscription":
        return "Recurring bill";
      default:
        return "Synced from server";
    }
  })();

  const purposeLabel =
    transaction.expensePurpose === "school" ? "School" : transaction.expensePurpose === "someoneElse" ? "Someone else" : "Personal";

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: "Transaction",
          headerLargeTitle: false,
          headerRight: () =>
            editing ? (
              <Pressable onPress={save} hitSlop={10}>
                <Text style={{ color: palette.blue, fontSize: 17, fontWeight: "600" }}>Save</Text>
              </Pressable>
            ) : undefined,
          headerLeft: editing
            ? () => (
                <Pressable onPress={() => setEditing(false)} hitSlop={10}>
                  <Text style={{ color: palette.blue, fontSize: 17 }}>Cancel</Text>
                </Pressable>
              )
            : undefined,
        }}
      />
      <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <View style={styles.hero}>
          <Icon name={paymentIconFor(transaction.description, transaction.category, amountMinor)} size={38} color={tone} />
          <Text style={[styles.direction, { color: tone }]}>{amountMinor >= 0 ? "Received" : "Spent"}</Text>
          <Text style={[styles.amount, { color: tone }]}>{formatMoney(Math.abs(amountMinor), currency)}</Text>
        </View>

        {editing ? (
          <Section title="Edit">
            <FormField label="Description" value={description} onChangeText={setDescription} />
            <CategoryPicker value={category} onChange={setCategory} />
            <Row title="Recurring bill" value={linkedBill?.name ?? "Not linked"} onPress={() => setBillPickerVisible(true)} />
          </Section>
        ) : null}

        <Section title="Payment details">
          <InfoRow label="Description" value={transaction.description} />
          {transaction.originalAmount ? (
            <>
              <InfoRow
                label="Original purchase"
                value={formatMoney(Math.abs(transaction.originalAmount.amountMinor), transaction.originalAmount.currency)}
              />
              <InfoRow label="Bank settlement" value={awaitingSettlement ? "Waiting for bank" : formatMoney(Math.abs(transaction.amount.amountMinor), transaction.amount.currency)} />
            </>
          ) : null}
          <InfoRow label="Category" value={transaction.category ?? "Uncategorized"} />
          <InfoRow label="Purpose" value={purposeLabel} />
          <InfoRow label="Direction" value={amountMinor < 0 ? "Money out" : "Money in"} />
          <Row
            title="Status"
            icon={transaction.pending ? "clock" : "checkCircle"}
            iconColor={transaction.pending ? palette.orange : palette.green}
            value={transaction.pending ? "Pending" : "Completed"}
            valueColor={transaction.pending ? palette.orange : palette.green}
          />
          <InfoRow label="Date" value={formatDate(transaction.bookedAt)} />
        </Section>

        <Section title="Account">
          <InfoRow label="Account" value={account?.name ?? "Unknown account"} />
          {account?.institution ? <InfoRow label="Institution" value={account.institution} /> : null}
          <InfoRow label="Currency" value={transaction.amount.currency} />
        </Section>

        {transaction.source === "transfer" ? (
          <Section title="Transfer">
            <InfoRow
              label={transaction.transferDirection === "outgoing" ? "To" : "From"}
              value={transferAccount?.name ?? "Unknown account"}
            />
          </Section>
        ) : null}

        <Section
          title="Recurring bill"
          footer="Ledgerly matches the original purchase currency when available. Foreign-currency bills can also be linked manually."
        >
          <Row
            icon="bill"
            title="Recurring bill"
            value={linkedBill?.name ?? "Not linked"}
            valueColor={linkedBill ? palette.label : palette.secondaryLabel}
            onPress={() => setBillPickerVisible(true)}
          />
        </Section>

        <Section title="Record information">
          <InfoRow label="Source" value={sourceLabel} />
          <InfoRow label="Last updated" value={formatDate(transaction.updatedAt)} />
          <View style={styles.idBlock}>
            <Text style={[styles.idLabel, { color: palette.secondaryLabel }]}>Transaction ID</Text>
            <Text selectable style={[styles.idValue, { color: palette.label }]}>
              {transaction.id}
            </Text>
          </View>
        </Section>

        <Section>
          <Row icon="edit" iconColor={palette.blue} title="Edit transaction" onPress={startEditing} showChevron={false} />
          <Row icon="trash" iconColor={palette.red} title="Delete transaction" destructive onPress={confirmDelete} showChevron={false} />
        </Section>
        <View style={{ height: 28 }} />
      </ScrollView>

      <Modal visible={billPickerVisible} animationType="slide" presentationStyle="pageSheet" onRequestClose={() => setBillPickerVisible(false)}>
        <Screen>
          <View style={styles.modalHeader}>
            <Text style={[styles.modalTitle, { color: palette.label }]}>Recurring bill</Text>
            <Pressable onPress={() => setBillPickerVisible(false)}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>Done</Text>
            </Pressable>
          </View>
          <ScrollView>
            <Row
              title="Not linked"
              accessory={!transaction.recurringPaymentId ? <Icon name="checkmark" size={16} color={palette.blue} /> : undefined}
              onPress={() => {
                updateTransaction(transaction.id, { recurringPaymentId: null });
                setBillPickerVisible(false);
              }}
            />
            {bills.map((bill) => (
              <Row
                key={bill.id}
                title={bill.name}
                subtitle={`${formatMoney(bill.amountMinor, bill.currency)} · next ${formatDate(bill.nextDate)}`}
                accessory={transaction.recurringPaymentId === bill.id ? <Icon name="checkmark" size={16} color={palette.blue} /> : undefined}
                onPress={() => {
                  updateTransaction(transaction.id, { recurringPaymentId: bill.id });
                  setBillPickerVisible(false);
                }}
              />
            ))}
          </ScrollView>
        </Screen>
      </Modal>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 0, gap: 22, paddingBottom: 120 },
  hero: { alignItems: "center", gap: 6, paddingVertical: 18 },
  direction: { fontSize: 17, fontWeight: "600" },
  amount: { fontSize: 34, fontWeight: "700", fontVariant: ["tabular-nums"] },
  idBlock: { paddingHorizontal: 16, paddingVertical: 10, gap: 4 },
  idLabel: { fontSize: 12 },
  idValue: { fontSize: 12, fontFamily: "Menlo" },
  modalHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", padding: 20 },
  modalTitle: { fontSize: 20, fontWeight: "700" },
});
