import type { Account } from "@ledgerly/contracts";
import { useFocusEffect, useRouter } from "expo-router";
import { useCallback, useState } from "react";
import { ScrollView, StyleSheet, View } from "react-native";
import { Button, Card, Dialog, List, Portal, RadioButton, SegmentedButtons, Text, TextInput, useTheme } from "react-native-paper";
import { cachedAccounts, createLocalTransaction } from "../../src/db";
import { parseMoney } from "../../src/finance";
import { RowIcon, Screen } from "../../src/ui";

export default function Add() {
  const router = useRouter();
  const theme = useTheme();
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [showingTransaction, setShowingTransaction] = useState(false);
  const [accountId, setAccountId] = useState("");
  const [description, setDescription] = useState("");
  const [amount, setAmount] = useState("");
  const [direction, setDirection] = useState("out");
  const [error, setError] = useState<string>();
  useFocusEffect(useCallback(() => { const accounts = cachedAccounts(); setAccounts(accounts); setAccountId(current => accounts.some(a => a.id === current) ? current : accounts[0]?.id ?? ""); }, []));
  const minor = parseMoney(amount);
  const valid = !!description.trim() && minor !== null && minor > 0 && accounts.some(account => account.id === accountId);
  const close = () => { setShowingTransaction(false); setAmount(""); setDescription(""); setError(undefined); };
  const save = () => {
    if (!valid || minor === null) return;
    try { createLocalTransaction({ accountId, description, amountMinor: direction === "out" ? -minor : minor }); close(); router.navigate("/activity"); }
    catch (error) { setError(error instanceof Error ? error.message : "Could not save transaction"); }
  };
  return <Screen title="Add" overlay={<Portal><Dialog visible={showingTransaction} onDismiss={close}>
    <Dialog.Title>New transaction</Dialog.Title>
    <Dialog.ScrollArea><ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={styles.form}>
      <SegmentedButtons value={direction} onValueChange={setDirection} buttons={[{ value: "out", label: "Money out", icon: "arrow-top-right" }, { value: "in", label: "Money in", icon: "arrow-bottom-left" }]} />
      <TextInput mode="outlined" label="Description" value={description} onChangeText={setDescription} />
      <TextInput mode="outlined" label={`Amount (${accounts.find(a => a.id === accountId)?.balance.currency ?? ""})`} value={amount} onChangeText={setAmount} keyboardType="decimal-pad" />
      <Text variant="labelLarge">Account</Text>
      <RadioButton.Group value={accountId} onValueChange={setAccountId}>{accounts.map(account => <RadioButton.Item key={account.id} label={`${account.name} · ${account.balance.currency}`} value={account.id} />)}</RadioButton.Group>
      {error && <Text style={{ color: theme.colors.error }}>{error}</Text>}
    </ScrollView></Dialog.ScrollArea>
    <Dialog.Actions><Button onPress={close}>Cancel</Button><Button disabled={!valid} onPress={save}>Save</Button></Dialog.Actions>
  </Dialog></Portal>}>
    <View style={styles.form}><Text variant="titleMedium">What would you like to add?</Text>
      <Card mode="contained">
        <List.Item title="Transaction" description="Record money in or out" onPress={() => accounts.length ? setShowingTransaction(true) : router.push("/accounts?create=1")} left={props => <RowIcon style={props.style} icon="cash-plus" />} right={props => <List.Icon {...props} icon="chevron-right" />} />
        <List.Item title="Account" description="Bank, savings, cash or card" onPress={() => router.push("/accounts?create=1")} left={props => <RowIcon style={props.style} icon="bank-plus" />} right={props => <List.Icon {...props} icon="chevron-right" />} />
        <List.Item title="Recurring payment" description="Subscriptions and regular bills" onPress={() => router.push("/activity?create=1")} left={props => <RowIcon style={props.style} icon="calendar-plus" />} right={props => <List.Icon {...props} icon="chevron-right" />} />
      </Card>
      {!accounts.length && <Text variant="bodyMedium">Create an account before recording transactions.</Text>}
    </View>
  </Screen>;
}
const styles = StyleSheet.create({ form: { gap: 12, paddingVertical: 12 } });
