import { useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { recordMoney } from "../../src/actions";
import { cachedAccounts } from "../../src/db";
import { formatMoney, parseMinorUnits } from "../../src/format";
import { quickSpendCategories, type Account } from "../../src/types";
import { quickSpendState, useCacheVersion } from "../../src/store";
import { useTheme } from "../../src/theme";
import { AccountPicker } from "../../src/components/AccountPicker";
import { PrimaryButton, SecondaryButton } from "../../src/components/Buttons";
import { AmountHeader } from "../../src/components/Fields";
import { Row, Section } from "../../src/components/List";
import { SheetScreen } from "../../src/components/Sheet";
import { StepHeader } from "../../src/components/StepFlow";
import { Icon, paymentIconFor } from "../../src/components/Icon";
import { success } from "../../src/haptics";

export default function QuickSpendSheet() {
  const router = useRouter();
  const palette = useTheme();
  const version = useCacheVersion();
  const accounts = useMemo(() => cachedAccounts(), [version]);

  const lastAccountId = quickSpendState.accountId();
  const initialAccount =
    accounts.find((account) => account.id === lastAccountId) ??
    accounts.find((account) => account.kind === "cash") ??
    accounts[0];
  const lastCategory = quickSpendState.category();

  const [step, setStep] = useState(initialAccount ? 1 : 0);
  const [accountId, setAccountId] = useState(initialAccount?.id ?? "");
  const [amount, setAmount] = useState("");
  const [reimbursement, setReimbursement] = useState(false);

  const account = accounts.find((item) => item.id === accountId);
  const currency = account?.balance.currency ?? "TWD";
  const parsedAmount = parseMinorUnits(amount) ?? 0;
  const orderedCategories = [lastCategory, ...quickSpendCategories.filter((category) => category !== lastCategory)];
  const titles = ["Choose account", "Enter amount", "Choose category"];

  const selectAccount = (next: Account) => {
    setAccountId(next.id);
    quickSpendState.setAccountId(next.id);
    setStep(1);
  };

  const save = (category: string) => {
    if (!account || parsedAmount <= 0) return;
    recordMoney({
      direction: "moneyOut",
      accountId: account.id,
      amountMinor: parsedAmount,
      currency,
      description: category,
      category,
      date: new Date(),
      expensePurpose: "personal",
      expectsReimbursement: reimbursement,
    });
    quickSpendState.setAccountId(account.id);
    quickSpendState.setCategory(category);
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
          <PrimaryButton title="Enter amount" icon="chevronRight" tone="red" disabled={!account} onPress={() => setStep(1)} />
        ) : step === 1 ? (
          <PrimaryButton title="Choose category" icon="chevronRight" tone="red" disabled={parsedAmount <= 0} onPress={() => setStep(2)} />
        ) : (
          <SecondaryButton
            title="Add more details"
            icon="bill"
            onPress={() => router.replace({ pathname: "/add/money", params: { direction: "out", accountId: account?.id ?? "", amount } } as never)}
          />
        )
      }
    >
      {step === 0 ? (
        <>
          <StepHeader current={1} total={3} instruction="Which account paid?" />
          <AccountPicker accounts={accounts} selectedId={accountId} onSelect={selectAccount} />
        </>
      ) : null}

      {step === 1 ? (
        <>
          <StepHeader current={2} total={3} instruction={account?.name ?? "Amount"} />
          <Section>
            <AmountHeader title="Purchase amount" amount={amount} onChangeAmount={setAmount} currency={currency} currencyLocked tone={palette.red} />
          </Section>
        </>
      ) : null}

      {step === 2 ? (
        <>
          <StepHeader current={3} total={3} instruction="Tap a category to save" />
          <Section>
            <Row
              title="I expect reimbursement"
              accessory={
                <View style={[styles.switch, { backgroundColor: reimbursement ? palette.green : palette.fill }]}>
                  <View style={[styles.knob, { alignSelf: reimbursement ? "flex-end" : "flex-start" }]} />
                </View>
              }
              onPress={() => setReimbursement(!reimbursement)}
            />
          </Section>
          <Section title="Category">
            {orderedCategories.map((category) => (
              <Pressable key={category} onPress={() => save(category)} style={styles.categoryRow}>
                <Icon name={paymentIconFor("", category, -1)} size={18} color={palette.red} />
                <Text style={[styles.categoryText, { color: palette.label }]}>{category}</Text>
                {category === lastCategory ? (
                  <Text style={{ color: palette.secondaryLabel, fontSize: 13 }}>Last used</Text>
                ) : null}
              </Pressable>
            ))}
          </Section>
          <Text style={[styles.hint, { color: palette.secondaryLabel }]}>
            {formatMoney(parsedAmount, currency)} from {account?.name ?? "account"}.
          </Text>
        </>
      ) : null}
    </SheetScreen>
  );
}

const styles = StyleSheet.create({
  categoryRow: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 16, paddingVertical: 13 },
  categoryText: { flex: 1, fontSize: 17, fontWeight: "500" },
  hint: { fontSize: 13, paddingHorizontal: 16 },
  switch: { width: 51, height: 31, borderRadius: 999, padding: 2, justifyContent: "center" },
  knob: { width: 27, height: 27, borderRadius: 999, backgroundColor: "#FFFFFF" },
});
