import { Stack, useRouter } from "expo-router";
import { useState } from "react";
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { APP_VERSION, compatibilityMessage, healthReady, serverConfig } from "../../../src/api";
import { cachedAccounts, cachedRecurringPayments, cachedTransactions } from "../../../src/db";
import { formatDate } from "../../../src/format";
import { useCacheVersion, useHiddenAmounts } from "../../../src/store";
import { useSession } from "../../../src/session";
import { useSync } from "../../../src/sync";
import { useTheme } from "../../../src/theme";
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

  const accounts = cachedAccounts().length;
  const transactions = cachedTransactions().length;
  const bills = cachedRecurringPayments().length;
  void version;

  const check = async () => {
    setChecking(true);
    try {
      await healthReady(apiUrl);
      setHealth("Ready");
      const config = await serverConfig(apiUrl);
      setServerVersion(config.serverVersion ?? "—");
      setCompatibility(compatibilityMessage(config));
      await refresh();
    } catch {
      setHealth("Unreachable");
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
      <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content}>
        <Section title="Sync">
          {localOnly ? (
            <>
              <InfoRow label="Where" value="On this iPhone" />
              <Row icon="server" title="Set up sync" showChevron={false} onPress={() => void configureSync()} />
            </>
          ) : (
            <>
              <InfoRow label="Account" value={username ?? "—"} />
              <Row icon="server" title="Server" value={apiUrl.replace(/^https?:\/\//, "")} onPress={() => router.push("/settings/server" as never)} />
              <Row icon="key" title="API keys" onPress={() => router.push("/settings/api-keys" as never)} />
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
                />
              ) : null}
              <Row
                icon="server"
                title={checking ? "Checking…" : "Check connection"}
                onPress={() => void check()}
                showChevron={false}
              />
              <Row icon="transfer" title="Sync now" onPress={() => void refresh()} showChevron={false} />
            </>
          )}
        </Section>

        <Section title="Display">
          <Row
            icon={hidden ? "eyeSlash" : "eye"}
            title="Hide financial amounts"
            showChevron={false}
            accessory={
              <View style={[styles.switch, { backgroundColor: hidden ? palette.green : palette.fill }]}>
                <View style={[styles.knob, { alignSelf: hidden ? "flex-end" : "flex-start" }]} />
              </View>
            }
            onPress={() => setHidden(!hidden)}
          />
        </Section>

        <Section title="About">
          <InfoRow label="App" value="Ledgerly" />
          <InfoRow label="Sync" value="Cursor-based /v1/sync" />
          <InfoRow label="Protocol" value="2" />
        </Section>

        <Section title="On this device" footer="Ledgerly keeps accounts, transactions, and bills in an on-device SQLite database, and the session token in the Keychain/Keystore.">
          <InfoRow label="Accounts" value={String(accounts)} />
          <InfoRow label="Transactions" value={String(transactions)} />
          <InfoRow label="Recurring bills" value={String(bills)} />
        </Section>

        {!localOnly ? (
          <Section>
            <Pressable onPress={confirmLogout} style={styles.logout}>
              <Text style={{ color: palette.red, fontSize: 17 }}>Log out</Text>
            </Pressable>
          </Section>
        ) : null}
        <View style={{ height: 28 }} />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 0, gap: 22, paddingBottom: 120 },
  switch: { width: 51, height: 31, borderRadius: 999, padding: 2, justifyContent: "center" },
  knob: { width: 27, height: 27, borderRadius: 999, backgroundColor: "#FFFFFF" },
  logout: { paddingHorizontal: 16, paddingVertical: 13, minHeight: 48, justifyContent: "center" },
});
