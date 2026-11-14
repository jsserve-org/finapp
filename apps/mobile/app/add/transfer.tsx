import { useLocalSearchParams, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { transfer } from "../../src/actions";
import { cachedAccounts } from "../../src/db";
import { formatMoney, parseMinorUnits } from "../../src/format";
import { useCacheVersion } from "../../src/store";
import { useTheme } from "../../src/theme";
import { AccountPicker } from "../../src/components/AccountPicker";
import { PrimaryButton } from "../../src/components/Buttons";
import { AmountHeader, FormField } from "../../src/components/Fields";
import { DateField } from "../../src/components/DateField";
import { InfoRow, Section } from "../../src/components/List";
import { SheetScreen } from "../../src/components/Sheet";
import { StepHeader } from "../../src/components/StepFlow";
import { success } from "../../src/haptics";
import type { Account } from "../../src/types";

export default function TransferSheet() {
  const params = useLocalSearchParams<{ accountId?: string }>();
  const router = useRouter();
  const palette = useTheme();
  const version = useCacheVersion();
  const accounts = useMemo(() => cachedAccounts(), [version]);

  const preferred = accounts.find((account) => account.id === params.accountId);
  const [step, setStep] = useState(preferred ? 1 : 0);
  const [sourceId, setSourceId] = useState(preferred?.id ?? "");
  const [destinationId, setDestinationId] = useState("");
  const [amount, setAmount] = useState("");
  const [note, setNote] = useState("Transfer");
  const [date, setDate] = useState(new Date());

  const source = accounts.find((account) => account.id === sourceId);
  const destination = accounts.find((account) => account.id === destinationId);
  const destinations = accounts.filter((account) => account.id !== sourceId && account.balance.currency === source?.balance.currency);
  const parsedAmount = parseMinorUnits(amount) ?? 0;
  const titles = ["From account", "To account", "Transfer amount", "Additional information"];

  const selectSource = (account: Account) => {
    setSourceId(account.id);
    const next = accounts.find((item) => item.id !== account.id && item.balance.currency === account.balance.currency);
    setDestinationId(next?.id ?? "");
    setStep(1);
  };

  const save = () => {
    if (!source || !destination || parsedAmount <= 0) return;
    transfer({ amountMinor: parsedAmount, description: note.trim() || "Transfer", date, sourceId: source.id, destinationId: destination.id });
    success();
    router.back();
  };

  const headerLeft =
    step > 0 ? (
      <Pressable onPress={() => setStep(step - 1)} hitSlop={10}>
        <Text style={{ color: palette.blue, fontSize: 17 }}>Back</Text>
      </Pressable>
    ) : (
      <Pressable onPress={() => router.back()} hitSlop={10}>
        <Text style={{ color: palette.blue, fontSize: 17 }}>Cancel</Text>
      </Pressable>
    );

  return (
    <SheetScreen
      title={titles[step]}
      headerLeft={headerLeft}
      headerRight={
        step > 0 ? (
          <Pressable onPress={() => router.back()} hitSlop={10}>
            <Text style={{ color: palette.blue, fontSize: 17 }}>Cancel</Text>
          </Pressable>
        ) : undefined
      }
      footer={
        step === 0 ? (
          <PrimaryButton title="Choose destination" icon="chevronRight" disabled={!source} onPress={() => setStep(1)} />
        ) : step === 1 ? (
          <PrimaryButton title="Enter amount" icon="chevronRight" disabled={!destination} onPress={() => setStep(2)} />
        ) : step === 2 ? (
          <PrimaryButton title="Additional information" icon="chevronRight" disabled={parsedAmount <= 0} onPress={() => setStep(3)} />
        ) : (
          <PrimaryButton title="Transfer money" icon="transfer" disabled={parsedAmount <= 0} onPress={save} />
        )
      }
    >
      {step === 0 ? (
        <>
          <StepHeader current={1} total={4} instruction="Choose the account sending money" />
          <AccountPicker accounts={accounts} selectedId={sourceId} onSelect={selectSource} title="From" emptyMessage="Create an account before making a transfer." />
        </>
      ) : null}

      {step === 1 ? (
        <>
          <StepHeader current={2} total={4} instruction="Where should the money go?" />
          {destinations.length === 0 ? (
            <Text style={[styles.empty, { color: palette.secondaryLabel }]}>
              Add another {source?.balance.currency ?? ""} account to transfer money.
            </Text>
          ) : (
            <AccountPicker
              accounts={destinations}
              selectedId={destinationId}
              onSelect={(account) => {
                setDestinationId(account.id);
                setStep(2);
              }}
              title="To"
            />
          )}
        </>
      ) : null}

      {step === 2 ? (
        <>
          <StepHeader current={3} total={4} instruction={`${source?.name ?? ""} → ${destination?.name ?? ""}`} />
          <Section>
            <AmountHeader
              title="Transfer amount"
              amount={amount}
              onChangeAmount={setAmount}
              currency={source?.balance.currency ?? "TWD"}
              currencyLocked
            />
          </Section>
          {amount.length > 0 && parsedAmount <= 0 ? (
            <Text style={[styles.error, { color: palette.red }]}>Enter a valid amount greater than zero.</Text>
          ) : null}
        </>
      ) : null}

      {step === 3 ? (
        <>
          <StepHeader current={4} total={4} instruction="Review and transfer" />
          <Section title="Summary">
            <InfoRow label="From" value={source?.name ?? "—"} />
            <InfoRow label="To" value={destination?.name ?? "—"} />
            <InfoRow label="Amount" value={formatMoney(parsedAmount, source?.balance.currency ?? "TWD")} />
          </Section>
          <Section title="Optional details">
            <FormField label="Description" value={note} onChangeText={setNote} />
            <DateField value={date} onChange={setDate} />
          </Section>
        </>
      ) : null}
    </SheetScreen>
  );
}

const styles = StyleSheet.create({
  empty: { padding: 16, fontSize: 15 },
  error: { fontSize: 13, paddingHorizontal: 16 },
});
