import { useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { saveRecurringPayment } from "../actions";
import { cachedAccounts } from "../db";
import { formatMoney, parseMinorUnits } from "../format";
import { frequencies, type RecurringPayment, type TransactionFrequency } from "../types";
import { useCacheVersion } from "../store";
import { useTheme } from "../theme";
import { AccountPicker } from "../components/AccountPicker";
import { PrimaryButton } from "../components/Buttons";
import { DateField } from "../components/DateField";
import { AmountHeader, CategoryPicker, FormField } from "../components/Fields";
import { InfoRow, Row, Section } from "../components/List";
import { SheetScreen } from "../components/Sheet";
import { StepHeader } from "../components/StepFlow";
import { Icon } from "../components/Icon";
import { success } from "../haptics";

export function BillForm({ payment }: { payment?: RecurringPayment }) {
  const router = useRouter();
  const palette = useTheme();
  const version = useCacheVersion();
  const accounts = useMemo(() => cachedAccounts(), [version]);
  const editing = payment != null;

  const [step, setStep] = useState(0);
  const [accountId, setAccountId] = useState(payment?.accountId ?? accounts[0]?.id ?? "");
  const [amount, setAmount] = useState(payment ? (payment.amountMinor / 100).toFixed(2) : "");
  const [currency, setCurrency] = useState(payment?.currency ?? accounts[0]?.balance.currency ?? "TWD");
  const [frequency, setFrequency] = useState<TransactionFrequency>(payment?.frequency ?? "monthly");
  const [nextDate, setNextDate] = useState(payment ? new Date(payment.nextDate) : new Date());
  const [name, setName] = useState(payment?.name ?? "");
  const [category, setCategory] = useState(payment?.category ?? "Bills");
  const [isActive, setIsActive] = useState(payment?.isActive ?? true);

  const account = accounts.find((item) => item.id === accountId);
  const parsedAmount = parseMinorUnits(amount) ?? 0;
  const canSave = name.trim().length > 0 && parsedAmount > 0;

  const save = () => {
    if (!canSave) return;
    saveRecurringPayment({
      id: payment?.id,
      name,
      amountMinor: parsedAmount,
      currency,
      frequency,
      nextDate,
      accountId: accountId || undefined,
      category,
      isActive,
    });
    success();
    router.back();
  };

  const basicSections = (
    <>
      <Section title="Bill">
        <FormField label="Name" value={name} onChangeText={setName} placeholder="Rent, Netflix, gym…" />
        <CategoryPicker value={category} onChange={setCategory} />
      </Section>
      <Section title="Repeats">
        {frequencies.map((option) => (
          <Row
            key={option.value}
            title={option.label}
            accessory={frequency === option.value ? <Icon name="checkmark" size={16} color={palette.blue} /> : undefined}
            onPress={() => setFrequency(option.value)}
          />
        ))}
        <DateField label="Next payment" value={nextDate} onChange={setNextDate} />
      </Section>
      <Section title="Account" footer="Due dates create pending expense records and link matching payments. Ledgerly does not move money or charge the account.">
        <Row title="Pay from" value={account?.name ?? "Not selected"} onPress={() => setAccountId("")} />
        {accounts.map((option) => (
          <Row
            key={option.id}
            icon="account"
            title={option.name}
            subtitle={`${option.institution} · ${formatMoney(option.balance.amountMinor, option.balance.currency)}`}
            accessory={accountId === option.id ? <Icon name="checkCircle" size={18} color={palette.blue} /> : undefined}
            onPress={() => {
              setAccountId(option.id);
              setCurrency(option.balance.currency);
            }}
          />
        ))}
      </Section>
      <Section>
        <Row
          title="Active"
          accessory={
            <View style={[styles.switch, { backgroundColor: isActive ? palette.green : palette.fill }]}>
              <View style={[styles.knob, { alignSelf: isActive ? "flex-end" : "flex-start" }]} />
            </View>
          }
          onPress={() => setIsActive(!isActive)}
        />
      </Section>
    </>
  );

  if (editing) {
    return (
      <SheetScreen
        title="Edit recurring bill"
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
      >
        <Section>
          <AmountHeader title="Amount" amount={amount} onChangeAmount={setAmount} currency={currency} onChangeCurrency={setCurrency} autoFocus={false} />
        </Section>
        {basicSections}
      </SheetScreen>
    );
  }

  const titles = ["Choose account", "Enter amount", "Schedule", "Additional information"];

  return (
    <SheetScreen
      title={titles[step]}
      headerLeft={
        step > 0 ? (
          <Pressable onPress={() => setStep(step - 1)} hitSlop={10}>
            <Text style={{ color: palette.blue, fontSize: 17 }}>Back</Text>
          </Pressable>
        ) : (
          <Pressable onPress={() => router.back()} hitSlop={10}>
            <Text style={{ color: palette.blue, fontSize: 17 }}>Cancel</Text>
          </Pressable>
        )
      }
      headerRight={
        step > 0 ? (
          <Pressable onPress={() => router.back()} hitSlop={10}>
            <Text style={{ color: palette.blue, fontSize: 17 }}>Cancel</Text>
          </Pressable>
        ) : undefined
      }
      footer={
        step === 0 ? (
          <PrimaryButton title="Enter amount" icon="chevronRight" onPress={() => setStep(1)} />
        ) : step === 1 ? (
          <PrimaryButton title="Choose schedule" icon="chevronRight" disabled={parsedAmount <= 0} onPress={() => setStep(2)} />
        ) : step === 2 ? (
          <PrimaryButton title="Additional information" icon="chevronRight" onPress={() => setStep(3)} />
        ) : (
          <PrimaryButton title="Add recurring bill" icon="bill" disabled={!canSave} onPress={save} />
        )
      }
    >
      {step === 0 ? (
        <>
          <StepHeader current={1} total={4} instruction="Which account usually pays this bill?" />
          <AccountPicker
            accounts={accounts}
            selectedId={accountId}
            onSelect={(option) => {
              setAccountId(option.id);
              setCurrency(option.balance.currency);
              setStep(1);
            }}
            title="Pay from"
          />
          <Pressable
            onPress={() => {
              setAccountId("");
              setStep(1);
            }}
            style={[styles.noAccount, { borderColor: palette.separator }]}
          >
            <Icon name={accountId ? "circle" : "checkCircle"} size={18} color={accountId ? palette.tertiaryLabel : palette.blue} />
            <Text style={{ color: palette.label, fontSize: 17 }}>No account</Text>
          </Pressable>
        </>
      ) : null}

      {step === 1 ? (
        <>
          <StepHeader current={2} total={4} instruction={account?.name ?? "Recurring amount"} />
          <Section>
            <AmountHeader title="Amount" amount={amount} onChangeAmount={setAmount} currency={currency} onChangeCurrency={setCurrency} />
          </Section>
        </>
      ) : null}

      {step === 2 ? (
        <>
          <StepHeader current={3} total={4} instruction="When does it repeat?" />
          <Section title="Repeats">
            {frequencies.map((option) => (
              <Row
                key={option.value}
                title={option.label}
                accessory={frequency === option.value ? <Icon name="checkmark" size={16} color={palette.blue} /> : undefined}
                onPress={() => setFrequency(option.value)}
              />
            ))}
            <DateField label="Next payment" value={nextDate} onChange={setNextDate} />
          </Section>
        </>
      ) : null}

      {step === 3 ? (
        <>
          <StepHeader current={4} total={4} instruction="Review and save" />
          <Section title="Summary">
            <InfoRow label="Account" value={account?.name ?? "No account"} />
            <InfoRow label="Amount" value={formatMoney(parsedAmount, currency)} />
            <InfoRow label="Schedule" value={frequencies.find((option) => option.value === frequency)?.label ?? frequency} />
          </Section>
          <Section title="Bill">
            <FormField label="Name" value={name} onChangeText={setName} placeholder="Rent, Netflix, gym…" />
            <CategoryPicker value={category} onChange={setCategory} />
          </Section>
        </>
      ) : null}
    </SheetScreen>
  );
}

const styles = StyleSheet.create({
  switch: { width: 51, height: 31, borderRadius: 999, padding: 2, justifyContent: "center" },
  knob: { width: 27, height: 27, borderRadius: 999, backgroundColor: "#FFFFFF" },
  noAccount: { flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 16, paddingVertical: 12, borderTopWidth: StyleSheet.hairlineWidth },
});
