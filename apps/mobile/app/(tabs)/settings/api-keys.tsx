import { useEffect, useState } from "react";
import { Alert, Pressable, ScrollView, StyleSheet, Text } from "react-native";
import { createAPIKey, listAPIKeys, revokeAPIKey, type APIKeySummary } from "../../../src/api";
import { useSession } from "../../../src/session";
import { useTheme } from "../../../src/theme";
import { FormField } from "../../../src/components/Fields";
import { Row, Section, Screen } from "../../../src/components/List";

export default function APIKeysScreen() {
  const palette = useTheme();
  const { apiUrl, token } = useSession();
  const [keys, setKeys] = useState<APIKeySummary[]>([]);
  const [name, setName] = useState("");
  const [created, setCreated] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const load = async () => {
    if (!token) return;
    try {
      setKeys(await listAPIKeys(apiUrl, token));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Could not load API keys.");
    }
  };

  useEffect(() => {
    void load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const create = async () => {
    if (!token || !name.trim()) return;
    setBusy(true);
    setError(null);
    try {
      const key = await createAPIKey(apiUrl, token, name.trim());
      setCreated(key.key);
      setName("");
      await load();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Could not create the key.");
    } finally {
      setBusy(false);
    }
  };

  const revoke = (key: APIKeySummary) =>
    Alert.alert("Revoke key?", `Agents using “${key.name}” stop working immediately.`, [
      { text: "Cancel", style: "cancel" },
      {
        text: "Revoke",
        style: "destructive",
        onPress: async () => {
          if (!token) return;
          try {
            await revokeAPIKey(apiUrl, token, key.id);
            await load();
          } catch (reason) {
            setError(reason instanceof Error ? reason.message : "Could not revoke the key.");
          }
        },
      },
    ]);

  if (!token) {
    return (
      <Screen>
        <Text style={{ color: palette.secondaryLabel, padding: 20 }}>API keys need a sync account.</Text>
      </Screen>
    );
  }

  return (
    <Screen>
      <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Section title="New key" footer="Create named, revocable keys for agents and automations. The secret is shown once.">
          <FormField label="Name" value={name} onChangeText={setName} placeholder="Automation" autoCapitalize="words" />
        </Section>
        <Section>
          <Row
            icon="key"
            title={busy ? "Creating…" : "Create API key"}
            titleColor={busy || name.trim().length === 0 ? palette.tertiaryLabel : palette.blue}
            showChevron={false}
            onPress={() => {
              if (!busy && name.trim().length > 0) void create();
            }}
          />
        </Section>

        {created ? (
          <Section title="Copy this secret now">
            <Text selectable style={[styles.secret, { color: palette.label, backgroundColor: palette.fill }]}>
              {created}
            </Text>
            <Pressable onPress={() => setCreated(null)} style={styles.dismiss}>
              <Text style={{ color: palette.blue, fontSize: 17 }}>Done</Text>
            </Pressable>
          </Section>
        ) : null}

        {error ? <Text style={{ color: palette.red, paddingHorizontal: 16 }}>{error}</Text> : null}

        <Section title="Active keys">
          {keys.length === 0 ? (
            <Text style={{ color: palette.secondaryLabel, padding: 16 }}>No API keys yet.</Text>
          ) : (
            keys.map((key) => (
              <Row
                key={key.id}
                icon="key"
                title={key.name}
                subtitle={`${key.prefix}…`}
                value="Revoke"
                valueColor={palette.red}
                onPress={() => revoke(key)}
              />
            ))
          )}
        </Section>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 18, paddingBottom: 40 },
  secret: { margin: 16, padding: 14, borderRadius: 12, fontSize: 15, fontFamily: "Menlo" },
  dismiss: { alignItems: "center", paddingVertical: 14 },
});
