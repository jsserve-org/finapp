import { Stack, useRouter } from "expo-router";
import { useCallback, useState } from "react";
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { APP_VERSION, compatibilityMessage, healthReady, serverConfig } from "../../../src/api";
import { cachedAccounts, cachedRecurringPayments, cachedTransactions } from "../../../src/db";
import { formatDate } from "../../../src/format";
import { useCacheVersion, useHiddenAmounts } from "../../../src/store";
import { useSession } from "../../../src/session";
import { useSync } from "../../../src/sync";
import { useTheme } from "../../../src/theme";
import { DestructiveButton } from "../../../src/components/Buttons";
import { InfoRow, Row, Section, Screen } from "../../../src/components/List";
import { Icon } from "../../../src/components/Icon";

export default function SettingsScreen() {
  const palette = useTheme();
  const router = useRouter();
  const version = useCacheVersion();
  const { localOnly, username, configureSync, logout, apiUrl } = useSession();
  const { pendingCount, lastSyncedAt, isOffline, refresh } = useSync();
  const [hidden, setHidden] = useHiddenAmounts();
  const [health, setHealth] = useState<string | null>(null);
  const [serverVersion, setServerVersion] = useState<string | null>(null);
  const [compatibility, setCompatibility] = useState<string | null>(null);
  const [checking, setChecking] = useState(false);

  const counts = useCallback(
    () => ({
      accounts: cachedAccounts().length,
      transactions: cachedTransactions().length,
      bills: cachedRecurringPayments().length,
    }),
    [],
  );
  const totals = counts();

  const check = async () => {
    setChecking(true);
    try {
      await healthReady(apiUrl);
      setHealth("ready");
      const config = await serverConfig(apiUrl);
      setServerVersion(config.serverVersion ?? "—");
      setCompatibility(compatibilityMessage(config));
      await refresh();
    } catch {
      setHealth("unreachable");
    } finally {
      setChecking(false);
    }
  };

  const confirmLogout = () =>
    Alert.alert("Log out?", "Your local copy stays on this device; the server session is revoked.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Log out",
        style: "destructive",
        onPress: () => {
          void logout();
          router.replace("/login");
        },
      },
    ]);

  return (
    <Screen>
      <Stack.Screen options={{ title: "Settings", headerLargeTitle: true }} />
      <ScrollView contentContainerStyle={styles.content}>
        <Section title="Sync">
          {localOnly ? (
            <>
              <Row icon="person" title="On this phone" subtitle="Your data stays local until you enable sync." />
              <Row icon="server" iconColor={palette.blue} title="Set up sync" onPress={() => void configureSync()} />
            </>
          ) : (
            <>
              <InfoRow label="Account" value={username ?? "—"} />
              <Row icon="server" title="Server" subtitle={apiUrl} onPress={() => router.push("/(tabs)/settings/server" as never)} />
              <Row icon="key" title="API keys" subtitle="For agents and automations" onPress={() => router.push("/(tabs)/settings/api-keys" as never)} />
              <InfoRow label="Status" value={health ?? (isOffline ? "Offline" : "Up to date")} />
              <InfoRow label="Last sync" value={lastSyncedAt ? formatDate(lastSyncedAt) : "—"} />
              <InfoRow label="Pending changes" value={String(pendingCount)} />
              <InfoRow label="App version" value={APP_VERSION} />
              <InfoRow label="Server version" value={serverVersion ?? "—"} />
              {compatibility ? (
                <Row
                  icon={compatibility.startsWith("App and") || compatibility.startsWith("App update") ? "checkCircle" : "warning"}
                  iconColor={compatibility.startsWith("App and") || compatibility.startsWith("App update") ? palette.green : palette.red}
                  title={compatibility}
                  onPress={() => setCompatibility(null)}
                />
              ) : null}
              <Pressable onPress={() => void check()} disabled={checking} style={styles.checkRow}>
                <Icon name="server" size={17} color={palette.blue} />
                <Text style={{ color: palette.blue, fontSize: 17 }}>{checking ? "Checking…" : "Check connection"}</Text>
              </Pressable>
              <Row icon="transfer" title="Sync now" onPress={() => void refresh()} />
            </>
          )}
        </Section>

        <Section title="Display">
          <Row
            icon={hidden ? "eyeSlash" : "eye"}
            title="Hide financial amounts"
            accessory={
              <View style={[styles.switch, { backgroundColor: hidden ? palette.green : palette.fill }]}>
                <View style={[styles.knob, { alignSelf: hidden ? "flex-end" : "flex-start" }]} />
              </View>
            }
            onPress={() => setHidden(!hidden)}
          />
        </Section>

        <Section title="On this device" footer="Ledgerly keeps transactions and bills in an on-device SQLite database, and the session token in the Keychain/Keystore.">
          <InfoRow label="Accounts" value={String(totals.accounts)} />
          <InfoRow label="Transactions" value={String(totals.transactions)} />
          <InfoRow label="Recurring bills" value={String(totals.bills)} />
        </Section>

        <Section title="Privacy">
          <Row icon="lock" title="No analytics or tracking" subtitle="OCR and screenshots stay on this phone." />
          <Row icon="info" title="Sync protocol" subtitle="Cursor-based /v1/sync · protocol 2" />
        </Section>

        {!localOnly ? <DestructiveButton title="Log out" onPress={confirmLogout} icon="person" /> : null}
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 22, paddingBottom: 120 },
  checkRow: { flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 16, paddingVertical: 13 },
  switch: { width: 51, height: 31, borderRadius: 999, padding: 2, justifyContent: "center" },
  knob: { width: 27, height: 27, borderRadius: 999, backgroundColor: "#FFFFFF" },
});
