import { Stack, useRouter } from "expo-router";
import { useEffect, useRef, useState } from "react";
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { authenticate, serverConfig } from "../src/api";
import { useSession } from "../src/session";
import { useTheme } from "../src/theme";
import { FormField } from "../src/components/Fields";
import { Row, Section, Screen } from "../src/components/List";
import { success } from "../src/haptics";

export default function LoginScreen() {
  const router = useRouter();
  const palette = useTheme();
  const session = useSession();
  const [apiUrl, setApiUrl] = useState(session.apiUrl);
  const [convexUrl, setConvexUrl] = useState(session.convexUrl);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [register, setRegister] = useState(false);
  const [working, setWorking] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [registrationEnabled, setRegistrationEnabled] = useState(true);
  const loadedConfig = useRef("");

  useEffect(() => {
    if (loadedConfig.current === apiUrl) return;
    const timer = setTimeout(() => {
      loadedConfig.current = apiUrl;
      void serverConfig(apiUrl)
        .then((config) => setRegistrationEnabled(config.registrationEnabled))
        .catch(() => undefined);
    }, 400);
    return () => clearTimeout(timer);
  }, [apiUrl]);

  const submit = async () => {
    if (!/^https?:\/\/.+/i.test(apiUrl) || !/^https?:\/\/.+/i.test(convexUrl)) {
      setError("Enter valid HTTP(S) endpoint URLs.");
      return;
    }
    setWorking(true);
    setError(null);
    try {
      const response = await authenticate(apiUrl, username.trim(), password, convexUrl, register);
      await session.login(response, apiUrl.replace(/\/$/, ""), convexUrl.replace(/\/$/, ""));
      success();
      router.replace("/insights");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Could not reach the server.");
    } finally {
      setWorking(false);
    }
  };

  const canSubmit = username.trim().length >= 3 && password.length >= 10 && !working;

  return (
    <Screen>
      <Stack.Screen
        options={{
          title: register ? "Create account" : "Ledgerly",
          headerLargeTitle: true,
          headerShadowVisible: false,
        }}
      />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView
          contentInsetAdjustmentBehavior="automatic"
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
        >
          <Section
            footer={register ? undefined : "Your data stays on this device until you sign in."}
          >
            <Text style={[styles.intro, { color: palette.secondaryLabel }]}>
              {register ? "Create credentials for your self-hosted server." : "Start locally, or sign in to sync across devices."}
            </Text>
            {!register ? (
              <Row
                icon="iphone"
                title="Continue on this iPhone"
                titleColor={palette.blue}
                showChevron={false}
                onPress={() => void session.continueLocally()}
              />
            ) : null}
          </Section>

          <Section title="Server" footer="Endpoints are saved on this device and are never replaced by server-advertised internal addresses.">
            <FormField label="API" value={apiUrl} onChangeText={setApiUrl} autoCapitalize="none" keyboardType="url" placeholder="http://localhost:3000" />
            <FormField label="Convex" value={convexUrl} onChangeText={setConvexUrl} autoCapitalize="none" keyboardType="url" placeholder="http://localhost:3210" />
          </Section>

          <Section title="Account">
            <FormField label="Username" value={username} onChangeText={setUsername} autoCapitalize="none" placeholder="Username" />
            <FormField label="Password" value={password} onChangeText={setPassword} secureTextEntry autoCapitalize="none" placeholder="10+ characters" />
            {error ? <Text style={[styles.error, { color: palette.red }]}>{error}</Text> : null}
            <Row
              title={working ? "Connecting…" : register ? "Create account" : "Log in"}
              titleColor={canSubmit ? palette.blue : palette.tertiaryLabel}
              showChevron={false}
              onPress={() => {
                if (canSubmit) void submit();
              }}
            />
            {register || registrationEnabled ? (
              <Row
                title={register ? "Already have an account? Log in" : "Need an account? Register"}
                titleColor={palette.blue}
                showChevron={false}
                onPress={() => {
                  setRegister(!register);
                  setError(null);
                }}
              />
            ) : null}
          </Section>

          <Text style={[styles.footnote, { color: palette.secondaryLabel }]}>
            Registration and login passwords are sent only to the server you choose. Use HTTPS outside your own network.
          </Text>
          <View style={{ height: 24 }} />
        </ScrollView>
      </KeyboardAvoidingView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 0, gap: 22, paddingBottom: 40 },
  intro: { fontSize: 15, lineHeight: 20, paddingHorizontal: 16, paddingTop: 10 },
  error: { fontSize: 13, paddingHorizontal: 16, paddingVertical: 6 },
  footnote: { fontSize: 12, lineHeight: 17, paddingHorizontal: 16, textAlign: "center" },
});
