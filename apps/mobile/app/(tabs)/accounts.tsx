import type { Account } from "@ledgerly/contracts";
import { useFocusEffect, useLocalSearchParams, useRouter } from "expo-router";
import { useCallback, useMemo, useState } from "react";
import { StyleSheet, View } from "react-native";
import { Appbar, Avatar, Button, Card, Dialog, List, Portal, Text, TextInput } from "react-native-paper";
import { currencyTotals, parseMoney } from "../../src/finance";
import { cachedAccounts, createLocalAccount } from "../../src/db";
import { RowIcon, Screen, useAmounts, useMoneyColors } from "../../src/ui";

export default function Accounts() {
  const { money, hidden, toggle } = useAmounts();
  const colors = useMoneyColors();
  const params = useLocalSearchParams<{ create?: string }>();
  const router = useRouter();
  const [currency, setCurrency] = useState("TWD");
  const [accounts, setAccounts] = useState<Account[]>([]);
  const [showingNew, setShowingNew] = useState(false);
  const [name, setName] = useState("");
  const [balance, setBalance] = useState("");
  useFocusEffect(useCallback(() => {
    setAccounts(cachedAccounts());
    if (params.create === "1") { setShowingNew(true); router.setParams({ create: undefined }); }
  }, [params.create, router]));
  const totals = useMemo(() => currencyTotals(accounts), [accounts]);
  const openingBalance = parseMoney(balance.trim() || "0");
  const valid = !!name.trim() && openingBalance !== null && /^[A-Z]{3}$/.test(currency);

  const close = () => { setShowingNew(false); setName(""); setBalance(""); };
  const save = () => {
    if (!valid || openingBalance === null) return;
    createLocalAccount({ name: name.trim(), institution: "Manual", kind: "checking", amountMinor: openingBalance, currency });
    setAccounts(cachedAccounts());
    close();
  };

  return <Screen title="Accounts" actions={<><Appbar.Action icon={hidden ? "eye-off-outline" : "eye-outline"} accessibilityLabel={hidden ? "Show financial amounts" : "Hide financial amounts"} onPress={toggle} /><Appbar.Action icon="plus" accessibilityLabel="New account" onPress={() => setShowingNew(true)} /></>} overlay={<>
    <Portal>
      <Dialog visible={showingNew} onDismiss={close}>
        <Dialog.Icon icon="wallet-plus-outline" />
        <Dialog.Title style={styles.center}>New account</Dialog.Title>
        <Dialog.Content style={styles.form}>
          <TextInput mode="outlined" label="Account name" value={name} onChangeText={setName} autoFocus />
          <TextInput mode="outlined" label="Opening balance" value={balance} onChangeText={setBalance} keyboardType="decimal-pad" />
          <TextInput mode="outlined" label="Currency" value={currency} onChangeText={value => setCurrency(value.toUpperCase())} autoCapitalize="characters" maxLength={3} />
          <Text variant="bodySmall">Saved on this phone. You can turn on sync later.</Text>
        </Dialog.Content>
        <Dialog.Actions>
          <Button onPress={close}>Cancel</Button>
          <Button disabled={!valid} onPress={save}>Save</Button>
        </Dialog.Actions>
      </Dialog>
    </Portal>
  </>}>
    <View style={styles.summary}>
      {totals.map(([currency, total]) => <Text key={currency} variant="headlineLarge" numberOfLines={1} adjustsFontSizeToFit>{money(total, currency)}</Text>)}
      <Text variant="bodyMedium">Across {accounts.length} account{accounts.length === 1 ? "" : "s"}</Text>
    </View>
    {!!accounts.length && <Card mode="contained">
      {accounts.map((account) => <List.Item key={account.id} title={account.name} description={`${account.institution} · ${account.kind}`}
        left={(props) => <RowIcon style={props.style} icon="bank-outline" />}
        right={() => <Text variant="titleSmall" style={[styles.amount, account.balance.amountMinor < 0 && { color: colors.expense }]}>{money(account.balance.amountMinor, account.balance.currency)}</Text>} />)}
    </Card>}
    {!accounts.length && <Card mode="outlined">
      <Card.Title title="No accounts yet" subtitle="Create one on this phone. Sync is optional." subtitleNumberOfLines={2} left={(props) => <Avatar.Icon {...props} icon="wallet-outline" />} />
    </Card>}
  </Screen>;
}

const styles = StyleSheet.create({
  summary: { gap: 4, paddingHorizontal: 4 },
  amount: { alignSelf: "center" },
  fab: { position: "absolute", right: 16, bottom: 16 },
  center: { textAlign: "center" },
  form: { gap: 12 },
});
