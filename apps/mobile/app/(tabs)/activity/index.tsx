import { Stack, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { ActionSheetIOS, Modal, Platform, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from "react-native";
import { cachedAccounts, cachedRecurringPayments, cachedTransactionsNewest } from "../../../src/db";
import { formatDate, formatMoney } from "../../../src/format";
import { transactionPresentation } from "../../../src/insights";
import { useCacheVersion, useHiddenAmounts } from "../../../src/store";
import { useSession } from "../../../src/session";
import { useSync } from "../../../src/sync";
import { useTheme } from "../../../src/theme";
import { PrimaryButton, SecondaryButton } from "../../../src/components/Buttons";
import { DateField } from "../../../src/components/DateField";
import { EmptyState, Row, Section, Screen } from "../../../src/components/List";
import { Icon, paymentIconFor } from "../../../src/components/Icon";
import { frequencyLabel } from "../../../src/types";

type DateFilter = "last7" | "last30" | "last90" | "thisYear" | "all" | "custom";

const filterLabels: Record<DateFilter, string> = {
  last7: "Last 7 days",
  last30: "Last 30 days",
  last90: "Last 90 days",
  thisYear: "This year",
  all: "All loaded",
  custom: "Custom",
};

export default function ActivityScreen() {
  const palette = useTheme();
  const router = useRouter();
  const version = useCacheVersion();
  const { refresh, isSyncing } = useSync();
  const { token } = useSession();
  const [hidden] = useHiddenAmounts();
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState<DateFilter>("last90");
  const [customStart, setCustomStart] = useState(() => new Date(Date.now() - 1000 * 60 * 60 * 24 * 90));
  const [customEnd, setCustomEnd] = useState(() => new Date());
  const [customVisible, setCustomVisible] = useState(false);
  const [showAllBills, setShowAllBills] = useState(false);
  const [limit, setLimit] = useState(50);

  const accounts = useMemo(() => cachedAccounts(), [version]);
  const bills = useMemo(() => cachedRecurringPayments(), [version]);
  const transactions = useMemo(() => cachedTransactionsNewest(500), [version]);

  const visible = useMemo(() => {
    const accountsById = new Map(accounts.map((account) => [account.id, account]));
    const billsById = new Map(bills.map((bill) => [bill.id, bill]));
    const now = new Date();
    const start = (() => {
      switch (filter) {
        case "last7":
          return new Date(now.getTime() - 7 * 86400000);
        case "last30":
          return new Date(now.getTime() - 30 * 86400000);
        case "last90":
          return new Date(now.getTime() - 90 * 86400000);
        case "thisYear":
          return new Date(now.getFullYear(), 0, 1);
        case "custom":
          return new Date(Math.min(customStart.getTime(), customEnd.getTime()));
        default:
          return null;
      }
    })();
    const end =
      filter === "custom"
        ? new Date(Math.max(customStart.getTime(), customEnd.getTime()) + 86400000)
        : filter === "all"
          ? null
          : now;
    const needle = search.trim().toLowerCase();

    return transactions.filter((transaction) => {
      const booked = new Date(transaction.bookedAt);
      if (start && booked < start) return false;
      if (end && booked > end) return false;
      if (!needle) return true;
      const account = accountsById.get(transaction.accountId);
      const bill = transaction.recurringPaymentId ? billsById.get(transaction.recurringPaymentId) : undefined;
      return [
        transaction.description,
        transaction.category ?? "",
        transaction.amount.currency,
        account?.name ?? "",
        account?.institution ?? "",
        bill?.name ?? "",
        formatMoney(transaction.amount.amountMinor, transaction.amount.currency),
        formatDate(transaction.bookedAt),
      ].some((field) => field.toLowerCase().includes(needle));
    });
  }, [accounts, bills, customEnd, customStart, filter, search, transactions]);

  const pickFilter = () => {
    const presets: DateFilter[] = ["last7", "last30", "last90", "thisYear", "all"];
    const options = ["Cancel", ...presets.map((key) => filterLabels[key]), "Custom range…"];
    if (Platform.OS === "ios") {
      ActionSheetIOS.showActionSheetWithOptions({ options, cancelButtonIndex: 0, title: "Date range" }, (index) => {
        if (index === 0) return;
        if (index === options.length - 1) {
          setCustomVisible(true);
          return;
        }
        setFilter(presets[index - 1]);
        setLimit(50);
      });
      return;
    }
    const next = presets[(presets.indexOf(filter as never) + 1) % presets.length];
    setFilter(next);
    setLimit(50);
  };

  const shownBills = showAllBills ? bills : bills.slice(0, 3);
  const shown = (amount: number, currency: string) => (hidden ? "••••" : formatMoney(amount, currency));

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: "Activity",
          headerLargeTitle: true,
          headerSearchBarOptions: {
            placeholder: "Search transactions",
            onChangeText: (event) => setSearch(event.nativeEvent.text),
          },
        }}
      />
      <ScrollView
        contentContainerStyle={styles.content}
        keyboardShouldPersistTaps="handled"
        refreshControl={
          <RefreshControl refreshing={isSyncing} onRefresh={() => void refresh()} enabled={token != null} tintColor={palette.secondaryLabel} />
        }
      >
        <View style={styles.quickActions}>
          <PrimaryButton title="Spend money" icon="plus" tone="blue" onPress={() => router.push("/add/money?direction=out" as never)} />
          <SecondaryButton title="Add recurring bill" icon="bill" onPress={() => router.push("/add/bill" as never)} />
          <Text style={[styles.caption, { color: palette.secondaryLabel }]}>
            Expenses are one-time transactions. Recurring bills repeat on a schedule.
          </Text>
        </View>

        <Section title="Recurring bills" footer={bills.length > 3 ? "Tap a bill to see its history and edit its schedule." : undefined}>
          {bills.length === 0 ? (
            <EmptyState icon="bill" title="No recurring bills" message="Add rent, subscriptions, or any repeating payment." />
          ) : (
            shownBills.map((bill) => (
              <Row
                key={bill.id}
                icon="bill"
                title={bill.name}
                subtitle={`${bill.isActive ? "" : "Paused · "}${frequencyLabel(bill.frequency)} · next ${formatDate(bill.nextDate, "short")}`}
                value={shown(-bill.amountMinor, bill.currency)}
                valueColor={palette.label}
                onPress={() => router.push({ pathname: "/activity/bill/[id]", params: { id: bill.id } } as never)}
              />
            ))
          )}
          {bills.length > 3 ? (
            <Pressable onPress={() => setShowAllBills(!showAllBills)} style={styles.moreRow}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>
                {showAllBills ? "Show fewer" : `Show all ${bills.length}`}
              </Text>
            </Pressable>
          ) : null}
        </Section>

        <Section
          title="Bills & transactions"
          headerAccessory={
            <Pressable onPress={pickFilter} style={styles.filterButton}>
              <Icon name="calendar" size={12} color={palette.blue} />
              <Text style={{ color: palette.blue, fontSize: 13, fontWeight: "600" }}>
                {filter === "custom"
                  ? `${formatDate(customStart, "short")}–${formatDate(customEnd, "short")}`
                  : filterLabels[filter]}
              </Text>
            </Pressable>
          }
          footer={`Showing ${Math.min(limit, visible.length)} of ${visible.length} matching transactions. Ledgerly loads at most the newest 500 records to keep Activity responsive.`}
        >
          {transactions.length === 0 ? (
            <EmptyState icon="activity" title="No activity" message="Transactions you add or sync will appear here." />
          ) : visible.length === 0 ? (
            <EmptyState
              icon="search"
              title={search ? "No search results" : "No transactions in this range"}
              message={search ? "Try a different search or date range." : "Choose a wider date range to see older activity."}
            />
          ) : (
            visible.slice(0, limit).map((transaction) => {
              const { amountMinor, currency, awaitingSettlement } = transactionPresentation(transaction);
              const bill = transaction.recurringPaymentId ? bills.find((item) => item.id === transaction.recurringPaymentId) : undefined;
              return (
                <Row
                  key={transaction.id}
                  icon={paymentIconFor(transaction.description, transaction.category, amountMinor)}
                  iconColor={amountMinor >= 0 ? palette.green : palette.red}
                  title={transaction.description}
                  subtitle={`${amountMinor >= 0 ? "Received" : "Spent"} · ${transaction.category ?? "Uncategorized"}${awaitingSettlement ? " · bank charge pending" : ""}${bill ? ` · ${bill.name}` : ""}`}
                  value={shown(amountMinor, currency)}
                  valueColor={amountMinor >= 0 ? palette.green : palette.label}
                  onPress={() =>
                    router.push({ pathname: "/activity/transaction/[id]", params: { id: transaction.id } } as never)
                  }
                />
              );
            })
          )}
          {visible.length > limit ? (
            <Pressable onPress={() => setLimit(limit + 50)} style={styles.moreRow}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>Show 50 more</Text>
            </Pressable>
          ) : null}
        </Section>
      </ScrollView>

      <Modal visible={customVisible} animationType="slide" presentationStyle="pageSheet" onRequestClose={() => setCustomVisible(false)}>
        <Screen>
          <View style={styles.modalHeader}>
            <Text style={[styles.modalTitle, { color: palette.label }]}>Custom dates</Text>
            <Pressable
              onPress={() => {
                setFilter("custom");
                setLimit(50);
                setCustomVisible(false);
              }}
            >
              <Text style={{ color: palette.blue, fontSize: 17 }}>Apply</Text>
            </Pressable>
          </View>
          <Section title="Date range">
            <DateField label="From" value={customStart} onChange={setCustomStart} />
            <DateField label="Through" value={customEnd} onChange={setCustomEnd} />
          </Section>
        </Screen>
      </Modal>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 22, paddingBottom: 120 },
  quickActions: { gap: 10 },
  caption: { fontSize: 13, lineHeight: 18, paddingHorizontal: 4 },
  moreRow: { alignItems: "center", paddingVertical: 14 },
  filterButton: { flexDirection: "row", alignItems: "center", gap: 5 },
  modalHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", padding: 20 },
  modalTitle: { fontSize: 20, fontWeight: "700" },
});
