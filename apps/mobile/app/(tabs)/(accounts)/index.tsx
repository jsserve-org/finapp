import { Stack, useRouter } from "expo-router";
import { useMemo } from "react";
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { cachedAccounts, cachedHoldings } from "../../../src/db";
import { formatMoney } from "../../../src/format";
import { netWorthByCurrency } from "../../../src/insights";
import { useCacheVersion, useHiddenAmounts } from "../../../src/store";
import { useSession } from "../../../src/session";
import { useSync } from "../../../src/sync";
import { useTheme } from "../../../src/theme";
import { EmptyState, Row, Section, Screen } from "../../../src/components/List";
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
                <Icon name="addCircle" size={21} color={palette.blue} />
              </Pressable>
            </View>
          ),
        }}
      />
      <ScrollView
        contentContainerStyle={styles.content}
        refreshControl={
          <RefreshControl refreshing={isSyncing} onRefresh={() => void refresh()} enabled={token != null} tintColor={palette.secondaryLabel} />
        }
      >
        <Section title="Total">
          {totals.length === 0 ? (
            <Row title="Balance" value={hidden ? "••••" : formatMoney(0, "TWD")} valueColor={palette.label} />
          ) : (
            totals.map((total) => (
              <Row
                key={total.currency}
                title={total.currency}
                value={hidden ? "••••" : formatMoney(total.amount, total.currency)}
                valueColor={palette.label}
              />
            ))
          )}
          <Row title="Accounts" value={String(accounts.length)} />
        </Section>

        <Section title="Accounts">
          {accounts.length === 0 ? (
            <EmptyState
              icon="account"
              title="No accounts"
              message="Create an account on this device. Sync is optional."
              action={
                <Pressable onPress={() => router.push("/account/new" as never)} style={{ paddingVertical: 8 }}>
                  <Text style={{ color: palette.blue, fontSize: 17, fontWeight: "600" }}>Create account</Text>
                </Pressable>
              }
            />
          ) : (
            accounts.map((account) => (
              <Row
                key={account.id}
                icon={accountIcon(account.kind)}
                title={account.name}
                subtitle={`${account.institution} · ${accountKindLabel(account.kind)}`}
                value={hidden ? "••••" : formatMoney(account.balance.amountMinor, account.balance.currency)}
                valueColor={palette.label}
                onPress={() => router.push({ pathname: "/(tabs)/(accounts)/[id]", params: { id: account.id } } as never)}
              />
            ))
          )}
        </Section>

        <Section footer="Shared credit cards stay visible here but are left out of your own net worth.">
          <Row
            icon="info"
            iconColor={palette.secondaryLabel}
            title="Local-first"
            subtitle="Accounts you create stay on this device until sync is enabled."
          />
        </Section>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 22, paddingBottom: 120 },
  headerButtons: { flexDirection: "row", alignItems: "center", gap: 18 },
});
