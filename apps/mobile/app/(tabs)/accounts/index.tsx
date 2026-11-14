import { Stack, useRouter } from "expo-router";
import { useMemo } from "react";
import { Pressable, RefreshControl, ScrollView, StyleSheet, View } from "react-native";
import { cachedAccounts, cachedHoldings } from "../../../src/db";
import { formatMoney } from "../../../src/format";
import { netWorthByCurrency } from "../../../src/insights";
import { useCacheVersion, useHiddenAmounts } from "../../../src/store";
import { useSession } from "../../../src/session";
import { useSync } from "../../../src/sync";
import { useTheme } from "../../../src/theme";
import { EmptyState, InfoRow, Row, Section, Screen, ValueRow } from "../../../src/components/List";
import { Icon, accountIcon } from "../../../src/components/Icon";
import { accountKindLabel } from "../../../src/types";

export default function AccountsScreen() {
  const palette = useTheme();
  const version = useCacheVersion();
  const { refresh, isSyncing } = useSync();
  const { token } = useSession();
  const [hidden, setHidden] = useHiddenAmounts();
  const router = useRouter();

  const accounts = useMemo(() => cachedAccounts(), [version]);
  const totals = useMemo(() => netWorthByCurrency(accounts, cachedHoldings()), [accounts, version]);
  const shown = (amount: number, currency: string) => (hidden ? "••••" : formatMoney(amount, currency));

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: "Accounts",
          headerLargeTitle: true,
          headerRight: () => (
            <View style={styles.headerButtons}>
              <Pressable onPress={() => setHidden(!hidden)} hitSlop={10} accessibilityLabel={hidden ? "Show financial amounts" : "Hide financial amounts"}>
                <Icon name={hidden ? "eyeSlash" : "eye"} size={19} color={palette.blue} />
              </Pressable>
              <Pressable onPress={() => router.push("/account/new" as never)} hitSlop={10} accessibilityLabel="Add account">
                <Icon name="plus" size={20} color={palette.blue} />
              </Pressable>
            </View>
          ),
        }}
      />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl refreshing={isSyncing} onRefresh={() => void refresh()} enabled={token != null} tintColor={palette.secondaryLabel} />
        }
      >
        <Section title="Total">
          {totals.length === 0 ? (
            <ValueRow label="Balance" value={shown(0, "TWD")} emphasis />
          ) : (
            totals.map((total) => <ValueRow key={total.currency} label={total.currency} value={shown(total.amount, total.currency)} emphasis />)
          )}
          <InfoRow label="Accounts" value={String(accounts.length)} />
        </Section>

        <Section title="Accounts">
          {accounts.length === 0 ? (
            <>
              <EmptyState icon="account" title="No accounts" message="Create an account on this device. Sync is optional." />
              <Row title="Create account" titleColor={palette.blue} showChevron={false} onPress={() => router.push("/account/new" as never)} />
            </>
          ) : (
            accounts.map((account) => (
              <Row
                key={account.id}
                icon={accountIcon(account.kind)}
                title={account.name}
                subtitle={`${account.institution} · ${accountKindLabel(account.kind)}`}
                value={shown(account.balance.amountMinor, account.balance.currency)}
                valueColor={palette.label}
                strongValue
                onPress={() => router.push({ pathname: "/accounts/[id]", params: { id: account.id } } as never)}
              />
            ))
          )}
        </Section>
        <View style={{ height: 28 }} />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 0, gap: 22, paddingBottom: 120 },
  headerButtons: { flexDirection: "row", alignItems: "center", gap: 18 },
  createRow: { flexDirection: "row", alignItems: "center" },
});
