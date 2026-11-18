import type { Transaction } from "@ledgerly/contracts";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import { useCallback, useState } from "react";
import { StyleSheet, View } from "react-native";
import { Appbar, Avatar, Button, Card, Chip, Dialog, List, Portal, Text, TextInput, useTheme } from "react-native-paper";
import { parseMoney } from "../../src/finance";
import { cachedRecurringPayments, cachedTransactions, createRecurringPayment, type RecurringPayment } from "../../src/db";
import { RowIcon, Screen, useAmounts, useMoneyColors } from "../../src/ui";

const frequencyLabel: Record<RecurringPayment["frequency"], string> = { weekly: "Weekly", everyTwoWeeks: "Every 2 weeks", monthly: "Monthly", yearly: "Yearly", everyTwoYears: "Every 2 years" };
const frequencies = Object.keys(frequencyLabel) as RecurringPayment["frequency"][];
const today = () => new Date().toISOString().slice(0, 10);

export default function Activity() {
  const theme = useTheme();
  const colors = useMoneyColors();
  const { money, hidden, toggle } = useAmounts();
  const params = useLocalSearchParams<{ create?: string }>();
  const router = useRouter();
  const [currency, setCurrency] = useState("TWD");
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [recurring, setRecurring] = useState<RecurringPayment[]>([]);
  const [showingNew, setShowingNew] = useState(false);
  const [name, setName] = useState("");
  const [amount, setAmount] = useState("");
  const [nextDate, setNextDate] = useState(today);
  const [frequency, setFrequency] = useState<RecurringPayment["frequency"]>("monthly");
  const reload = useCallback(() => { setTransactions(cachedTransactions()); setRecurring(cachedRecurringPayments()); }, []);
  useFocusEffect(useCallback(() => {
    reload();
    if (params.create === "1") { setShowingNew(true); router.setParams({ create: undefined }); }
  }, [reload, params.create, router]));

  const amountMinor = parseMoney(amount);
  const valid = !!name.trim() && amountMinor !== null && amountMinor > 0 && /^[A-Z]{3}$/.test(currency) && !Number.isNaN(Date.parse(nextDate));
  const close = () => { setShowingNew(false); setName(""); setAmount(""); setNextDate(today()); setFrequency("monthly"); };
  const save = () => {
    if (!valid || amountMinor === null) return;
    createRecurringPayment({ name: name.trim(), amountMinor, currency, frequency, nextDate: new Date(nextDate).toISOString(), category: "Bills" });
    reload();
    close();
  };

  return <Screen title="Activity" actions={<><Appbar.Action icon={hidden ? "eye-off-outline" : "eye-outline"} accessibilityLabel={hidden ? "Show financial amounts" : "Hide financial amounts"} onPress={toggle} /><Appbar.Action icon="plus" accessibilityLabel="Add recurring payment" onPress={() => setShowingNew(true)} /></>} overlay={<>
    <Portal>
      <Dialog visible={showingNew} onDismiss={close}>
        <Dialog.Icon icon="calendar-sync-outline" />
        <Dialog.Title style={styles.center}>New recurring payment</Dialog.Title>
        <Dialog.ScrollArea>
          <View style={styles.form}>
            <TextInput mode="outlined" label="Payment name" value={name} onChangeText={setName} autoFocus />
            <TextInput mode="outlined" label="Amount" value={amount} onChangeText={setAmount} keyboardType="decimal-pad" />
            <TextInput mode="outlined" label="Currency" value={currency} onChangeText={value => setCurrency(value.toUpperCase())} autoCapitalize="characters" maxLength={3} />
            <TextInput mode="outlined" label="Next payment (YYYY-MM-DD)" value={nextDate} onChangeText={setNextDate} />
            <Text variant="labelLarge">Repeats</Text>
            <View style={styles.chips}>
              {frequencies.map((value) => <Chip key={value} selected={frequency === value} showSelectedCheck onPress={() => setFrequency(value)}>{frequencyLabel[value]}</Chip>)}
            </View>
            <Text variant="bodySmall">Ledgerly only tracks this schedule. It never moves money.</Text>
          </View>
        </Dialog.ScrollArea>
        <Dialog.Actions>
          <Button onPress={close}>Cancel</Button>
          <Button disabled={!valid} onPress={save}>Save</Button>
        </Dialog.Actions>
      </Dialog>
    </Portal>
  </>}>
    <View>
      <Text variant="titleMedium" style={styles.section}>Recurring payments</Text>
      <Card mode="contained">
        {recurring.map((item) => <List.Item key={item.id} title={item.name} description={`${frequencyLabel[item.frequency]} · next ${new Date(item.nextDate).toLocaleDateString()}`}
          left={(props) => <RowIcon style={props.style} icon="repeat" />}
          right={() => <Text variant="titleSmall" style={[styles.amount, { color: colors.expense }]}>{money(-item.amountMinor, item.currency)}</Text>} />)}
        {!recurring.length && <List.Item title="Plan your regular bills" description="Rent, subscriptions, or anything that repeats" onPress={() => setShowingNew(true)}
          left={(props) => <RowIcon style={props.style} icon="calendar-blank-outline" />}
          right={(props) => <List.Icon {...props} icon="chevron-right" />} />}
      </Card>
    </View>

    <View>
      <Text variant="titleMedium" style={styles.section}>Transactions</Text>
      <Card mode="contained">
        {transactions.map((item) => {
          const incoming = item.amount.amountMinor > 0;
          return <List.Item key={item.id} title={item.description} description={item.pending ? "Pending" : item.category ?? "Uncategorized"}
            left={(props) => <Avatar.Icon {...props} size={40} icon={incoming ? "arrow-bottom-left" : "arrow-top-right"}
              color={incoming ? colors.income : colors.expense}
              style={{ backgroundColor: incoming ? theme.colors.primaryContainer : theme.colors.tertiaryContainer }} />}
            right={() => <Text variant="titleSmall" style={[styles.amount, { color: incoming ? colors.income : colors.expense }]}>{money(item.amount.amountMinor, item.amount.currency)}</Text>} />;
        })}
        {!transactions.length && <List.Item title="No activity yet" description="Transactions you add or sync show up here" left={(props) => <List.Icon {...props} icon="receipt-text-outline" />} />}
      </Card>
    </View>
  </Screen>;
}

const styles = StyleSheet.create({
  section: { marginBottom: 8, marginLeft: 4 },
  amount: { alignSelf: "center" },
  fab: { position: "absolute", right: 16, bottom: 16 },
  center: { textAlign: "center" },
  form: { gap: 12, paddingVertical: 12 },
  chips: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
});
