import { useLocalSearchParams, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { Pressable, StyleSheet, Text } from "react-native";
import { updateAccount } from "../../../src/actions";
import { cachedAccounts } from "../../../src/db";
import { accountKinds, type AccountKind } from "../../../src/types";
import { useCacheVersion } from "../../../src/store";
import { useTheme } from "../../../src/theme";
import { FormField } from "../../../src/components/Fields";
import { EmptyState, InfoRow, Row, Section, Screen } from "../../../src/components/List";
import { SheetScreen } from "../../../src/components/Sheet";
import { Icon } from "../../../src/components/Icon";
import { success } from "../../../src/haptics";

export default function EditAccountSheet() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const router = useRouter();
  const palette = useTheme();
  const version = useCacheVersion();
  const account = useMemo(() => cachedAccounts().find((item) => item.id === id), [id, version]);
  const [name, setName] = useState(account?.name ?? "");
  const [institution, setInstitution] = useState(account?.institution ?? "");
  const [kind, setKind] = useState<AccountKind>((account?.kind as AccountKind) ?? "checking");

  if (!account) {
    return (
      <Screen>
        <EmptyState icon="account" title="Account not found" message="It may have been deleted on another device." />
      </Screen>
    );
  }

  const canSave = name.trim().length > 0;
  const save = () => {
    if (!canSave) return;
    updateAccount(account.id, { name, institution, kind });
    success();
    router.back();
  };

  return (
    <SheetScreen
      title="Edit account"
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
      <Section title="Account">
        <FormField label="Name" value={name} onChangeText={setName} />
        <FormField label="Institution" value={institution} onChangeText={setInstitution} />
        <InfoRow label="Currency" value={account.balance.currency} />
      </Section>
      <Section title="Type" footer="Use Add money, Spend, or Transfer to change the balance so every adjustment has a transaction record.">
        {accountKinds.map((option) => (
          <Row
            key={option.kind}
            title={option.label}
            accessory={kind === option.kind ? <Icon name="checkmark" size={16} color={palette.blue} /> : undefined}
            onPress={() => setKind(option.kind)}
          />
        ))}
      </Section>
    </SheetScreen>
  );
}

const styles = StyleSheet.create({});
