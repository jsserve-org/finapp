import { Pressable, StyleSheet, Text, View } from "react-native";
import { formatMoney } from "../format";
import { useTheme } from "../theme";
import { Icon, accountIcon } from "./Icon";
import { Section } from "./List";
import { accountKindLabel, type Account } from "../types";

export function AccountPicker({
  accounts,
  selectedId,
  onSelect,
  title = "Account",
  emptyMessage = "Create an account before recording money.",
}: {
  accounts: Account[];
  selectedId: string;
  onSelect: (account: Account) => void;
  title?: string;
  emptyMessage?: string;
}) {
  const palette = useTheme();
  const tone = palette.blue;
  return (
    <Section title={title}>
      {accounts.length === 0 ? (
        <Text style={[styles.empty, { color: palette.secondaryLabel }]}>{emptyMessage}</Text>
      ) : (
        accounts.map((account) => {
          const selected = account.id === selectedId;
          return (
            <Pressable key={account.id} onPress={() => onSelect(account)} style={styles.row}>
              <Icon name={accountIcon(account.kind)} size={21} color={tone} />
              <View style={{ flex: 1, gap: 2 }}>
                <Text style={[styles.title, { color: palette.label }]}>{account.name}</Text>
                <Text style={[styles.subtitle, { color: palette.secondaryLabel }]} numberOfLines={1}>
                  {`${account.institution} · ${accountKindLabel(account.kind)} · ${formatMoney(account.balance.amountMinor, account.balance.currency)}`}
                </Text>
              </View>
              <Icon name={selected ? "checkCircle" : "circle"} size={20} color={selected ? tone : palette.tertiaryLabel} />
            </Pressable>
          );
        })
      )}
    </Section>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 16, paddingVertical: 11 },
  title: { fontSize: 17, fontWeight: "500" },
  subtitle: { fontSize: 13 },
  empty: { padding: 16, fontSize: 15 },
});
