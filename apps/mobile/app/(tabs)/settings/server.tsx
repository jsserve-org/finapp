import { useState } from "react";
import { ScrollView, StyleSheet, Text } from "react-native";
import { healthReady } from "../../../src/api";
import { useSession } from "../../../src/session";
import { useTheme } from "../../../src/theme";
import { FormField } from "../../../src/components/Fields";
import { Row, Section, Screen } from "../../../src/components/List";

export default function ServerScreen() {
  const palette = useTheme();
  const { apiUrl, convexUrl, saveEndpoints } = useSession();
  const [api, setApi] = useState(apiUrl);
  const [convex, setConvex] = useState(convexUrl);
  const [message, setMessage] = useState<string | null>(null);
  const [ok, setOk] = useState(false);
  const [testing, setTesting] = useState(false);

  const save = async () => {
    const nextApi = api.trim().replace(/\/$/, "");
    const nextConvex = convex.trim().replace(/\/$/, "");
    if (!/^https?:\/\/.+/i.test(nextApi) || !/^https?:\/\/.+/i.test(nextConvex)) {
      setOk(false);
      setMessage("Enter valid HTTP(S) endpoint URLs.");
      return;
    }
    setTesting(true);
    setMessage(null);
    await saveEndpoints(nextApi, nextConvex);
    try {
      await healthReady(nextApi);
      setOk(true);
      setMessage("Connection ready");
    } catch {
      setOk(false);
      setMessage("Saved, but the API is unreachable.");
    } finally {
      setTesting(false);
    }
  };

  return (
    <Screen>
      <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Section title="Endpoints" footer="The app syncs through the API. The Convex address identifies your self-hosted deployment during login.">
          <FormField label="API" value={api} onChangeText={setApi} autoCapitalize="none" placeholder="https://api.example" />
          <FormField label="Convex" value={convex} onChangeText={setConvex} autoCapitalize="none" placeholder="https://sync.example" />
        </Section>
        <Section>
          <Row
            icon="checkCircle"
            title={testing ? "Testing…" : "Save and test"}
            titleColor={testing ? palette.tertiaryLabel : palette.blue}
            showChevron={false}
            onPress={() => {
              if (!testing) void save();
            }}
          />
        </Section>
        {message ? (
          <Text style={{ color: ok ? palette.green : palette.red, fontSize: 15, paddingHorizontal: 16 }}>{message}</Text>
        ) : null}
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 18 },
});
