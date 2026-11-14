import { useLocalSearchParams, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { recordMoney, type AccountEntryDirection } from "../../src/actions";
import { cachedAccounts } from "../../src/db";
import { formatMoney, parseMinorUnits } from "../../src/format";
import { useCacheVersion } from "../../src/store";
import { useTheme } from "../../src/theme";
import { AccountPicker } from "../../src/components/AccountPicker";
import { PrimaryButton } from "../../src/components/Buttons";
import { AmountHeader, CategoryPicker, FormField } from "../../src/components/Fields";
import { DateField } from "../../src/components/DateField";
import { InfoRow, Row, Section } from "../../src/components/List";
import { Icon } from "../../src/components/Icon";
import { SheetScreen } from "../../src/components/Sheet";
import { StepHeader } from "../../src/components/StepFlow";
import { success } from "../../src/haptics";
import type { Account } from "../../src/types";

export default function MoneySheet() {
  const params = useLocalSearchParams<{ direction?: string; accountId?: string; amount?: string }>();
  const direction: AccountEntryDirection = params.direction === "in" ? "moneyIn" : "moneyOut";
  const router = useRouter();
  const palette = useTheme();
  const version = useCacheVersion();
  const accounts = useMemo(() => cachedAccounts(), [version]);

  const initialAccount = accounts.find((account) => account.id === params.accountId);
  const [step, setStep] = useState(initialAccount ? 1 : 0);
  const [accountId, setAccountId] = useState(initialAccount?.id ?? "");
  const [amount, setAmount] = useState(params.amount ?? "");
  const [currency, setCurrency] = useState(initialAccount?.balance.currency ?? "TWD");
  const [description, setDescription] = useState(direction === "moneyIn" ? "Cash deposit" : "Cash expense");
  const [category, setCategory] = useState(direction === "moneyIn" ? "Deposit" : "Cash");
  const [date, setDate] = useState(new Date());
  const [purpose, setPurpose] = useState<"personal" | "school" | "someoneElse">("personal");
  const [expectsReimbursement, setExpectsReimbursement] = useState(false);

  const account = accounts.find((item) => item.id === accountId);
  const parsedAmount = parseMinorUnits(amount) ?? 0;
  const settlementPending = direction === "moneyOut" && account != null && currency !== account.balance.currency;
  const titles = ["Choose account", "Enter amount", "Additional information"];

  const selectAccount = (next: Account) => {
    setAccountId(next.id);
    setCurrency(next.balance.currency);
    setStep(1);
  };

  const save = () => {
    if (!account || parsedAmount <= 0) return;
    recordMoney({
      direction,
      accountId: account.id,
      amountMinor: parsedAmount,
      currency,
      description,
      category,
      date,
      expensePurpose: direction === "moneyOut" ? purpose : undefined,
      expectsReimbursement: direction === "moneyOut" && expectsReimbursement,
    });
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
          <PrimaryButton
            title="Enter amount"
            icon="chevronRight"
            tone={direction === "moneyIn" ? "green" : "red"}
            disabled={!account}
            onPress={() => setStep(1)}
          />
        ) : step === 1 ? (
          <PrimaryButton
            title="Additional information"
            icon="chevronRight"
            tone={direction === "moneyIn" ? "green" : "red"}
            disabled={parsedAmount <= 0}
            onPress={() => setStep(2)}
          />
        ) : (
          <PrimaryButton
            title={direction === "moneyIn" ? "Add money" : "Spend money"}
            icon={direction === "moneyIn" ? "addCircle" : "minusCircle"}
            tone={direction === "moneyIn" ? "green" : "red"}
            disabled={parsedAmount <= 0 || !account}
            onPress={save}
          />
        )
      }
    >
      {step === 0 ? (
        <>
          <StepHeader
            current={1}
            total={3}
            instruction={direction === "moneyIn" ? "Where should the money go?" : "Which account paid?"}
          />
          <AccountPicker accounts={accounts} selectedId={accountId} onSelect={selectAccount} />
        </>
      ) : null}

      {step === 1 ? (
        <>
          <StepHeader current={2} total={3} instruction={account?.name ?? "Amount"} />
          <Section>
            <AmountHeader
              title={direction === "moneyIn" ? "Money in" : "Purchase amount"}
              amount={amount}
              onChangeAmount={setAmount}
              currency={currency}
              onChangeCurrency={setCurrency}
              currencyLocked={direction === "moneyIn"}
              tone={direction === "moneyIn" ? palette.green : palette.red}
            />
          </Section>
          {amount.length > 0 && parsedAmount <= 0 ? (
            <Text style={[styles.error, { color: palette.red }]}>
              Enter a valid amount greater than zero, with at most two decimal places.
            </Text>
          ) : null}
        </>
      ) : null}

      {step === 2 ? (
        <>
          <StepHeader current={3} total={3} instruction="Review and save" />
          <Section title="Summary">
            <InfoRow label="Account" value={account?.name ?? "—"} />
            <InfoRow label="Amount" value={formatMoney(parsedAmount, currency)} />
            {settlementPending ? <InfoRow label="Bank charge" value="Waiting for bank" /> : null}
          </Section>
          <Section title="Optional details">
            <FormField label="Description" value={description} onChangeText={setDescription} />
            <CategoryPicker value={category} onChange={setCategory} />
            <DateField value={date} onChange={setDate} />
          </Section>
          {direction === "moneyOut" ? (
            <Section title="For" footer={settlementPending ? `Ledgerly records the purchase now. Your later bank import provides the final ${account?.balance.currency ?? "account"} charge.` : undefined}>
              <Row title="Personal" accessory={purpose === "personal" ? <Icon name="checkmark" size={16} color={palette.blue} /> : undefined} onPress={() => setPurpose("personal")} />
              <Row title="School" accessory={purpose === "school" ? <Icon name="checkmark" size={16} color={palette.blue} /> : undefined} onPress={() => setPurpose("school")} />
              <Row title="Someone else" accessory={purpose === "someoneElse" ? <Icon name="checkmark" size={16} color={palette.blue} /> : undefined} onPress={() => setPurpose("someoneElse")} />
              <Row
                title="I expect reimbursement"
                accessory={
                  <View style={[styles.switch, { backgroundColor: expectsReimbursement ? palette.green : palette.fill }]}>
                    <View style={[styles.knob, { alignSelf: expectsReimbursement ? "flex-end" : "flex-start" }]} />
                  </View>
                }
                onPress={() => setExpectsReimbursement(!expectsReimbursement)}
              />
            </Section>
          ) : null}
        </>
      ) : null}
    </SheetScreen>
  );
}

const styles = StyleSheet.create({
  error: { fontSize: 13, paddingHorizontal: 16 },
  switch: { width: 51, height: 31, borderRadius: 999, padding: 2, justifyContent: "center" },
  knob: { width: 27, height: 27, borderRadius: 999, backgroundColor: "#FFFFFF" },
});
