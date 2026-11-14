import { useRouter } from "expo-router";
import { useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { createAccount } from "../../src/actions";
import { defaultCurrency, parseMinorUnits } from "../../src/format";
import { accountKinds, type AccountKind } from "../../src/types";
import { useTheme } from "../../src/theme";
import { PrimaryButton } from "../../src/components/Buttons";
import { CurrencyRow, FormField } from "../../src/components/Fields";
import { Section } from "../../src/components/List";
import { SheetScreen } from "../../src/components/Sheet";
import { Icon } from "../../src/components/Icon";
import { success } from "../../src/haptics";

export default function NewAccountSheet() {
  const router = useRouter();
  const palette = useTheme();
  const [name, setName] = useState("");
  const [institution, setInstitution] = useState("");
  const [kind, setKind] = useState<AccountKind>("checking");
  const [balance, setBalance] = useState("");
  const [currency, setCurrency] = useState(defaultCurrency());

  const openingBalance = parseMinorUnits(balance === "" ? "0" : balance);
  const canSave = name.trim().length > 0 && openingBalance != null;

  const save = () => {
    if (!canSave || openingBalance == null) return;
    createAccount({ name, institution, kind, amountMinor: openingBalance, currency });
    success();
    router.back();
  };

  return (
    <SheetScreen
      title="New account"
      headerLeft={
        <Pressable onPress={() => router.back()} hitSlop={10}>
          <Text style={{ color: palette.blue, fontSize: 17 }}>Cancel</Text>
        </Pressable>
      }
      headerRight={
        <Pressable onPress={save} disabled={!canSave} hitSlop={10}>
          <Text style={{ color: canSave ? palette.blue : palette.tertiaryLabel, fontSize: 17, fontWeight: "600" }}>Save</Text>
        </Pressable>
      }
      footer={<PrimaryButton title="Create account" icon="addCircle" disabled={!canSave} onPress={save} />}
    >
      <Section title="Account">
        <FormField label="Name" value={name} onChangeText={setName} placeholder="Main checking" />
        <FormField label="Institution" value={institution} onChangeText={setInstitution} placeholder="Optional" />
      </Section>

      <Section title="Type">
        {accountKinds.map((option) => (
          <Pressable key={option.kind} onPress={() => setKind(option.kind)} style={styles.row}>
            <Text style={[styles.label, { color: palette.label }]}>{option.label}</Text>
            {kind === option.kind ? <Icon name="checkmark" size={16} color={palette.blue} /> : null}
          </Pressable>
        ))}
      </Section>

      <Section title="Opening balance" footer="This account is saved locally. You can enable sync later in Settings.">
        <FormField label="Balance" value={balance} onChangeText={setBalance} placeholder="0.00" keyboardType="decimal-pad" />
        <CurrencyRow currency={currency} onChange={setCurrency} />
      </Section>

      {kind === "sharedCredit" ? (
        <Text style={[styles.note, { color: palette.secondaryLabel }]}>
          Use this for a parent's or someone else's card. It stays visible in Accounts but is excluded from your own net worth.
        </Text>
      ) : null}

      {openingBalance == null ? (
        <Text style={{ color: palette.red, fontSize: 13, paddingHorizontal: 16 }}>
          Enter a valid opening balance with at most two decimal places.
        </Text>
      ) : null}
    </SheetScreen>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: 16, paddingVertical: 13 },
  label: { fontSize: 17 },
  note: { fontSize: 14, lineHeight: 20, paddingHorizontal: 16 },
});
