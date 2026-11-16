import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useMemo } from "react";
import { ActionSheetIOS, Alert, Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { cachedAccounts, cachedTransactions } from "../db";
import { formatMoney } from "../format";
import { deleteAccount } from "../actions";
import { transactionPresentation } from "../insights";
import { useCacheVersion } from "../store";
import { useTheme } from "../theme";
import { EmptyState, InfoRow, Row, Section, Screen, ValueRow } from "../components/List";
import { Icon, accountIcon, paymentIconFor, type IconName } from "../components/Icon";
import { accountKindLabel } from "../types";
import { warning } from "../haptics";

export default function AccountDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const palette = useTheme();
  const router = useRouter();
  const version = useCacheVersion();

  const account = useMemo(() => cachedAccounts().find((item) => item.id === id), [id, version]);
  const transactions = useMemo(
    () =>
      cachedTransactions()
        .filter((transaction) => transaction.accountId === id)
        .sort((a, b) => b.bookedAt.localeCompare(a.bookedAt))
        .slice(0, 500),
    [id, version],
  );

  if (!account) {
    return (
      <Screen>
        <Stack.Screen options={{ title: "Account" }} />
        <EmptyState icon="account" title="Account not found" message="It may have been deleted on another device." />
      </Screen>
    );
  }

  const confirmDelete = () => {
    Alert.alert(
      "Delete this account?",
      "This removes the account, its transactions, and linked recurring bills from this device and the sync server.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Delete account and its activity",
          style: "destructive",
          onPress: () => {
            deleteAccount(account.id);
            warning();
            router.back();
          },
        },
      ],
    );
  };

  const openMenu = () => {
    if (Platform.OS === "ios") {
      ActionSheetIOS.showActionSheetWithOptions(
        {
          options: ["Cancel", "Edit account", "Delete account"],
          destructiveButtonIndex: 2,
          cancelButtonIndex: 0,
          title: account.name,
        },
        (index) => {
          if (index === 1) router.push({ pathname: "/account/[id]/edit", params: { id: account.id } } as never);
          if (index === 2) confirmDelete();
        },
      );
      return;
    }
    router.push({ pathname: "/account/[id]/edit", params: { id: account.id } } as never);
  };

  const action = (title: string, icon: IconName, color: string, onPress: () => void) => (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        styles.tile,
        { backgroundColor: color + "1C" },
        pressed && { opacity: 0.7 },
      ]}
    >
      <Icon name={icon} size={22} color={color} />
      <Text style={[styles.tileLabel, { color }]} numberOfLines={1}>
        {title}
      </Text>
    </Pressable>
  );

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: account.name,
          headerLargeTitle: true,
          headerRight: () => (
            <Pressable onPress={openMenu} hitSlop={10} accessibilityLabel="Account options">
              <Icon name="ellipsis" size={20} color={palette.blue} />
            </Pressable>
          ),
        }}
      />
      <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content}>
        <Section title="Account">
          <ValueRow label="Balance" value={formatMoney(account.balance.amountMinor, account.balance.currency)} emphasis />
          <InfoRow label="Institution" value={account.institution} />
          <InfoRow label="Type" value={accountKindLabel(account.kind)} />
        </Section>

        <Section title="Actions">
          <View style={styles.grid}>
            {action("Add money", "addCircle", palette.green, () =>
              router.push({ pathname: "/add/money", params: { direction: "in", accountId: account.id } } as never),
            )}
            {action("Spend", "minusCircle", palette.red, () =>
              router.push({ pathname: "/add/money", params: { direction: "out", accountId: account.id } } as never),
            )}
            {action("Transfer", "transfer", palette.blue, () =>
              router.push({ pathname: "/add/transfer", params: { accountId: account.id } } as never),
            )}
            {action("Edit", "edit", "#8E8E93", () =>
              router.push({ pathname: "/account/[id]/edit", params: { id: account.id } } as never),
            )}
          </View>
        </Section>

        <Section title="Transactions">
          {transactions.length === 0 ? (
            <EmptyState icon="activity" title="No transactions" message="Money in, spending, and transfers appear here." />
          ) : (
            transactions.map((transaction) => {
              const { amountMinor, currency, awaitingSettlement } = transactionPresentation(transaction);
              return (
                <Row
                  key={transaction.id}
                  icon={paymentIconFor(transaction.description, transaction.category, amountMinor)}
                  iconColor={amountMinor >= 0 ? palette.green : palette.red}
                  title={transaction.description}
                  subtitle={`${transaction.source === "subscription" && transaction.pending ? "Expected payment" : amountMinor >= 0 ? "Received" : "Spent"} · ${transaction.category ?? "Uncategorized"}${awaitingSettlement ? " · bank charge pending" : ""}`}
                  value={formatMoney(amountMinor, currency)}
                  valueColor={amountMinor >= 0 ? palette.green : palette.red}
                  strongValue
                  onPress={() => router.push({ pathname: "/accounts/transaction/[id]", params: { id: transaction.id } } as never)}
                />
              );
            })
          )}
        </Section>
        <View style={{ height: 28 }} />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 0, gap: 22, paddingBottom: 120 },
  grid: { flexDirection: "row", flexWrap: "wrap", gap: 12, padding: 12 },
  tile: { width: "48%", minHeight: 58, borderRadius: 12, alignItems: "center", justifyContent: "center", gap: 7, flexGrow: 1, paddingHorizontal: 8 },
  tileLabel: { fontSize: 15, fontWeight: "600" },
});
