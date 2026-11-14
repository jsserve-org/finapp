import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { cachedAccounts, cachedRecurringPayments, cachedTransactions } from "../db";
import { formatDate, formatMoney } from "../format";
import { deleteAccount } from "../actions";
import { transactionPresentation } from "../insights";
import { useCacheVersion, useHiddenAmounts } from "../store";
import { useSync } from "../sync";
import { useTheme } from "../theme";
import { GlassSurface } from "../components/Glass";
import { DestructiveButton, PrimaryButton, SecondaryButton } from "../components/Buttons";
import { EmptyState, InfoRow, Row, Section, Screen } from "../components/List";
import { Icon, accountIcon, paymentIconFor } from "../components/Icon";
import { accountKindLabel } from "../types";
import { success, warning } from "../haptics";

export default function AccountDetailScreen() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const palette = useTheme();
  const router = useRouter();
  const version = useCacheVersion();
  const { refresh, isSyncing } = useSync();
  const [hidden] = useHiddenAmounts();
  const [limit, setLimit] = useState(50);

  const account = useMemo(() => cachedAccounts().find((item) => item.id === id), [id, version]);
  const transactions = useMemo(
    () =>
      cachedTransactions()
        .filter((transaction) => transaction.accountId === id)
        .sort((a, b) => b.bookedAt.localeCompare(a.bookedAt)),
    [id, version],
  );
  const bills = useMemo(() => cachedRecurringPayments().filter((payment) => payment.accountId === id), [id, version]);

  if (!account) {
    return (
      <Screen>
        <Stack.Screen options={{ title: "Account" }} />
        <EmptyState icon="account" title="Account not found" message="It may have been deleted on another device." />
      </Screen>
    );
  }

  const shown = (amount: number, currency: string) => (hidden ? "••••" : formatMoney(amount, currency));

  const confirmDelete = () => {
    Alert.alert(
      "Delete account?",
      "Its transactions and bills are removed from this device and synced as deletions.",
      [
        { text: "Cancel", style: "cancel" },
        {
          text: "Delete",
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

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: account.name,
          headerRight: () => (
            <Pressable onPress={() => router.push({ pathname: "/account/[id]/edit", params: { id: account.id } } as never)} hitSlop={10}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>Edit</Text>
            </Pressable>
          ),
        }}
      />
      <ScrollView
        contentContainerStyle={styles.content}
        refreshControl={<RefreshControl refreshing={isSyncing} onRefresh={() => void refresh()} tintColor={palette.secondaryLabel} />}
      >
        <GlassSurface style={styles.hero}>
          <View style={styles.heroTop}>
            <View style={[styles.heroIcon, { backgroundColor: palette.fill }]}>
              <Icon name={accountIcon(account.kind)} size={19} color={palette.blue} />
            </View>
            <View style={{ flex: 1 }}>
              <Text style={[styles.heroName, { color: palette.label }]}>{account.name}</Text>
              <Text style={[styles.heroSubtitle, { color: palette.secondaryLabel }]}>
                {account.institution} · {accountKindLabel(account.kind)}
              </Text>
            </View>
          </View>
          <Text style={[styles.heroValue, { color: palette.label }]}>
            {shown(account.balance.amountMinor, account.balance.currency)}
          </Text>
          <Text style={[styles.heroLabel, { color: palette.secondaryLabel }]}>Current balance</Text>
        </GlassSurface>

        <View style={styles.actions}>
          <PrimaryButton
            title="Add money"
            icon="addCircle"
            tone="green"
            onPress={() => router.push({ pathname: "/add/money", params: { direction: "in", accountId: account.id } } as never)}
          />
          <PrimaryButton
            title="Spend"
            icon="minusCircle"
            tone="red"
            onPress={() => router.push({ pathname: "/add/money", params: { direction: "out", accountId: account.id } } as never)}
          />
          <SecondaryButton
            title="Transfer"
            icon="transfer"
            onPress={() => router.push({ pathname: "/add/transfer", params: { accountId: account.id } } as never)}
          />
        </View>

        <Section title="Details">
          <InfoRow label="Type" value={accountKindLabel(account.kind)} />
          <InfoRow label="Institution" value={account.institution} />
          <InfoRow label="Currency" value={account.balance.currency} />
          <InfoRow label="Updated" value={formatDate(account.updatedAt)} />
        </Section>

        {bills.length > 0 ? (
          <Section title="Recurring bills" footer="Due dates create pending expense records and link matching payments.">
            {bills.map((bill) => (
              <Row
                key={bill.id}
                icon="bill"
                title={bill.name}
                subtitle={`${bill.isActive ? "" : "Paused · "}next ${formatDate(bill.nextDate)}`}
                value={shown(-bill.amountMinor, bill.currency)}
                valueColor={palette.label}
                onPress={() => router.push({ pathname: "/activity/bill/[id]", params: { id: bill.id } } as never)}
              />
            ))}
          </Section>
        ) : null}

        <Section
          title="History"
          footer={`Showing ${Math.min(limit, transactions.length)} of ${transactions.length} transactions.`}
        >
          {transactions.length === 0 ? (
            <EmptyState icon="activity" title="No transactions" message="Money in, spending, and transfers appear here." />
          ) : (
            transactions.slice(0, limit).map((transaction) => {
              const { amountMinor, currency } = transactionPresentation(transaction);
              return (
                <Row
                  key={transaction.id}
                  icon={paymentIconFor(transaction.description, transaction.category, amountMinor)}
                  iconColor={amountMinor >= 0 ? palette.green : palette.red}
                  title={transaction.description}
                  subtitle={`${amountMinor >= 0 ? "Received" : "Spent"} · ${transaction.category ?? "Uncategorized"} · ${formatDate(transaction.bookedAt, "short")}`}
                  value={shown(amountMinor, currency)}
                  valueColor={amountMinor >= 0 ? palette.green : palette.label}
                  onPress={() =>
                    router.push({ pathname: "/accounts/transaction/[id]", params: { id: transaction.id } } as never)
                  }
                />
              );
            })
          )}
          {transactions.length > limit ? (
            <Pressable onPress={() => setLimit(limit + 50)} style={styles.moreRow}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>Show 50 more</Text>
            </Pressable>
          ) : null}
        </Section>

        <DestructiveButton title="Delete account" onPress={confirmDelete} />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 22, paddingBottom: 130 },
  hero: { padding: 20, gap: 4 },
  heroTop: { flexDirection: "row", alignItems: "center", gap: 12, marginBottom: 12 },
  heroIcon: { width: 34, height: 34, borderRadius: 10, alignItems: "center", justifyContent: "center" },
  heroName: { fontSize: 17, fontWeight: "600" },
  heroSubtitle: { fontSize: 13 },
  heroValue: { fontSize: 38, fontWeight: "700", fontVariant: ["tabular-nums"] },
  heroLabel: { fontSize: 13 },
  actions: { gap: 10 },
  moreRow: { alignItems: "center", paddingVertical: 14 },
});
