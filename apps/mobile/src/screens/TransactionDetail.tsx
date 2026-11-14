import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, Modal, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from "react-native";
import {
  cachedAccounts,
  cachedRecurringPayments,
  cachedTransactions,
  getCached,
} from "../db";
import { formatDate, formatMoney } from "../format";
import { deleteTransaction, updateTransaction } from "../actions";
import { transactionPresentation } from "../insights";
import { useCacheVersion } from "../store";
import { useTheme } from "../theme";
import { GlassSurface } from "../components/Glass";
import { DestructiveButton, PrimaryButton, SecondaryButton } from "../components/Buttons";
import { CategoryPicker } from "../components/Fields";
import { FormField } from "../components/Fields";
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
  const linkedBill = useMemo(
    () => bills.find((bill) => bill.id === transaction?.recurringPaymentId),
    [bills, transaction],
  );
  const transferAccount = useMemo(
    () => cachedAccounts().find((item) => item.id === transaction?.transferAccountId),
    [transaction, version],
  );

  if (!transaction) {
    return (
      <Screen>
        <Stack.Screen options={{ title: "Transaction" }} />
        <EmptyState icon="activity" title="Transaction not found" message="It may have been deleted on another device." />
      </Screen>
    );
  }

  const { amountMinor, currency, awaitingSettlement } = transactionPresentation(transaction);
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
    Alert.alert(
      transaction.transferId ? "Delete transfer?" : "Delete transaction?",
      transaction.transferId
        ? "Both sides of the transfer are removed and the balances are restored."
        : "The account balance is restored and the deletion syncs to other devices.",
      [
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
      ],
    );
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

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: "Transaction",
          headerRight: () =>
            editing ? (
              <Pressable onPress={save} hitSlop={10}>
                <Text style={{ color: palette.blue, fontSize: 17, fontWeight: "600" }}>Save</Text>
              </Pressable>
            ) : (
              <Pressable onPress={startEditing} hitSlop={10}>
                <Text style={{ color: palette.blue, fontSize: 17 }}>Edit</Text>
              </Pressable>
            ),
          headerLeft: editing
            ? () => (
                <Pressable onPress={() => setEditing(false)} hitSlop={10}>
                  <Text style={{ color: palette.blue, fontSize: 17 }}>Cancel</Text>
                </Pressable>
              )
            : undefined,
        }}
      />
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <GlassSurface style={styles.hero}>
          <View style={[styles.heroIcon, { backgroundColor: palette.fill }]}>
            <Icon
              name={paymentIconFor(transaction.description, transaction.category, amountMinor)}
              size={22}
              color={amountMinor >= 0 ? palette.green : palette.red}
            />
          </View>
          <Text style={[styles.heroValue, { color: amountMinor >= 0 ? palette.green : palette.label }]}>
            {formatMoney(amountMinor, currency)}
          </Text>
          <Text style={[styles.heroTitle, { color: palette.label }]}>{transaction.description}</Text>
          <Text style={[styles.heroSubtitle, { color: palette.secondaryLabel }]}>
            {formatDate(transaction.bookedAt)}
            {account ? ` · ${account.name}` : ""}
          </Text>
          {awaitingSettlement ? (
            <View style={[styles.notice, { backgroundColor: palette.fill }]}>
              <Icon name="info" size={14} color={palette.secondaryLabel} />
              <Text style={{ color: palette.secondaryLabel, fontSize: 13 }}>
                Bank charge pending. Your later import provides the final amount.
              </Text>
            </View>
          ) : null}
        </GlassSurface>

        {editing ? (
          <Section title="Edit">
            <FormField label="Description" value={description} onChangeText={setDescription} autoCapitalize="sentences" />
            <CategoryPicker value={category} onChange={setCategory} />
            <Row
              title="Recurring bill"
              value={linkedBill?.name ?? "None"}
              onPress={() => setBillPickerVisible(true)}
            />
          </Section>
        ) : null}

        <Section title="Details">
          <InfoRow label="Category" value={transaction.category ?? "Uncategorized"} />
          <InfoRow label="Date" value={formatDate(transaction.bookedAt)} />
          {account ? <InfoRow label="Account" value={account.name} /> : null}
          <InfoRow label="Source" value={sourceLabel} />
          {transaction.originalAmount ? (
            <InfoRow
              label="Original"
              value={formatMoney(transaction.originalAmount.amountMinor, transaction.originalAmount.currency)}
            />
          ) : null}
          {transaction.expensePurpose ? (
            <InfoRow
              label="For"
              value={transaction.expensePurpose === "school" ? "School" : transaction.expensePurpose === "someoneElse" ? "Someone else" : "Personal"}
            />
          ) : null}
          {transaction.reimbursementStatus ? (
            <InfoRow label="Reimbursement" value={transaction.reimbursementStatus === "pending" ? "Expected" : "Settled"} />
          ) : null}
          {transferAccount ? (
            <InfoRow label={transaction.transferDirection === "outgoing" ? "To" : "From"} value={transferAccount.name} />
          ) : null}
          <InfoRow label="Pending" value={transaction.pending ? "Yes" : "No"} />
        </Section>

        {linkedBill ? (
          <Section title="Recurring bill">
            <Row
              icon="bill"
              title={linkedBill.name}
              subtitle={`next ${formatDate(linkedBill.nextDate)}`}
              value={formatMoney(-linkedBill.amountMinor, linkedBill.currency)}
              valueColor={palette.label}
              onPress={() => router.push({ pathname: "/activity/bill/[id]", params: { id: linkedBill.id } } as never)}
            />
            {!editing ? (
              <Row
                icon="close"
                iconColor={palette.red}
                title="Unlink bill"
                destructive
                onPress={() => {
                  updateTransaction(transaction.id, { recurringPaymentId: null });
                  success();
                }}
              />
            ) : null}
          </Section>
        ) : (
          <Section>
            <Row icon="bill" title="Link to a recurring bill" onPress={() => setBillPickerVisible(true)} />
          </Section>
        )}

        <DestructiveButton title="Delete transaction" onPress={confirmDelete} />
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
            <Pressable
              onPress={() => {
                updateTransaction(transaction.id, { recurringPaymentId: null });
                setBillPickerVisible(false);
              }}
              style={[styles.modalRow, { borderColor: palette.separator }]}
            >
              <Text style={{ color: palette.label, fontSize: 17 }}>None</Text>
              {!transaction.recurringPaymentId ? <Icon name="checkmark" size={16} color={palette.blue} /> : null}
            </Pressable>
            {bills.map((bill) => (
              <Pressable
                key={bill.id}
                onPress={() => {
                  updateTransaction(transaction.id, { recurringPaymentId: bill.id });
                  setBillPickerVisible(false);
                }}
                style={[styles.modalRow, { borderColor: palette.separator }]}
              >
                <View style={{ flex: 1 }}>
                  <Text style={{ color: palette.label, fontSize: 17 }}>{bill.name}</Text>
                  <Text style={{ color: palette.secondaryLabel, fontSize: 13 }}>
                    {formatMoney(bill.amountMinor, bill.currency)} · next {formatDate(bill.nextDate)}
                  </Text>
                </View>
                {transaction.recurringPaymentId === bill.id ? <Icon name="checkmark" size={16} color={palette.blue} /> : null}
              </Pressable>
            ))}
          </ScrollView>
        </Screen>
      </Modal>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 22, paddingBottom: 120 },
  hero: { padding: 20, gap: 6, alignItems: "center" },
  heroIcon: { width: 44, height: 44, borderRadius: 14, alignItems: "center", justifyContent: "center", marginBottom: 6 },
  heroValue: { fontSize: 36, fontWeight: "700", fontVariant: ["tabular-nums"] },
  heroTitle: { fontSize: 17, fontWeight: "600", textAlign: "center" },
  heroSubtitle: { fontSize: 13, textAlign: "center" },
  notice: { flexDirection: "row", gap: 6, alignItems: "center", paddingHorizontal: 12, paddingVertical: 8, borderRadius: 10, marginTop: 10 },
  modalHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", padding: 20 },
  modalTitle: { fontSize: 20, fontWeight: "700" },
  modalRow: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 20, paddingVertical: 14, borderTopWidth: StyleSheet.hairlineWidth },
});
