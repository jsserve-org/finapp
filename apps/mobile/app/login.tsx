import { useRouter } from "expo-router";
import { useEffect, useRef, useState } from "react";
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { authenticate, serverConfig } from "../src/api";
import { useSession } from "../src/session";
import { useTheme } from "../src/theme";
import { GlassSurface } from "../src/components/Glass";
import { PrimaryButton, SecondaryButton } from "../src/components/Buttons";
import { FormField } from "../src/components/Fields";
import { Section } from "../src/components/List";
import { Icon } from "../src/components/Icon";
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
  const [notice, setNotice] = useState<string | null>(null);
  const loadedConfig = useRef("");

  useEffect(() => {
    if (loadedConfig.current === apiUrl) return;
    const timer = setTimeout(() => {
      loadedConfig.current = apiUrl;
      void serverConfig(apiUrl)
        .then((config) => {
          setRegistrationEnabled(config.registrationEnabled);
          if (!session.convexUrl) setConvexUrl(config.convexUrl);
        })
        .catch(() => undefined);
    }, 400);
    return () => clearTimeout(timer);
  }, [apiUrl, session.convexUrl]);

  const submit = async () => {
    if (!/^https?:\/\/.+/i.test(apiUrl) || !/^https?:\/\/.+/i.test(convexUrl)) {
      setError("Enter valid HTTP(S) endpoint URLs.");
      return;
    }
    setWorking(true);
    setError(null);
    setNotice(null);
    try {
      const response = await authenticate(apiUrl, username.trim(), password, convexUrl, register);
      await session.login(response, apiUrl.replace(/\/$/, ""), convexUrl.replace(/\/$/, ""));
      success();
      router.replace("/");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "Could not reach the server.");
    } finally {
      setWorking(false);
    }
  };

  const canSubmit = username.trim().length >= 3 && password.length >= 10 && !working;

  return (
    <KeyboardAvoidingView style={{ flex: 1, backgroundColor: palette.background }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <View style={styles.hero}>
          <View style={[styles.heroIcon, { backgroundColor: palette.blue }]}>
            <Icon name="insights" size={26} color="#FFFFFF" weight="bold" />
          </View>
          <Text style={[styles.brand, { color: palette.label }]}>Ledgerly</Text>
          <Text style={[styles.tagline, { color: palette.secondaryLabel }]}>
            {register ? "Create credentials for your self-hosted server." : "Start locally, or sign in to sync across devices."}
          </Text>
        </View>

        {!register ? (
          <Pressable onPress={() => void session.continueLocally()} style={styles.localButtonWrap}>
            <GlassSurface style={styles.localButton} radius={16} interactive>
              <Icon name="person" size={19} color={palette.blue} />
              <Text style={{ color: palette.blue, fontSize: 17, fontWeight: "600" }}>Continue on this iPhone</Text>
            </GlassSurface>
          </Pressable>
        ) : null}

        <Section title="Server" footer="Endpoints are saved on this device and are never replaced by server-advertised internal addresses.">
          <FormField label="API" value={apiUrl} onChangeText={setApiUrl} autoCapitalize="none" keyboardType="url" placeholder="http://localhost:3000" />
          <FormField label="Convex" value={convexUrl} onChangeText={setConvexUrl} autoCapitalize="none" keyboardType="url" placeholder="http://localhost:3210" />
        </Section>

        <Section title="Account">
          <FormField label="Username" value={username} onChangeText={setUsername} autoCapitalize="none" placeholder="howard" />
          <FormField
            label="Password"
            value={password}
            onChangeText={setPassword}
            secureTextEntry
            autoCapitalize="none"
            placeholder="10+ characters"
          />
        </Section>

        {error ? <Text style={[styles.message, { color: palette.red }]}>{error}</Text> : null}
        {notice ? <Text style={[styles.message, { color: palette.green }]}>{notice}</Text> : null}

        <PrimaryButton
          title={working ? "Connecting…" : register ? "Create account" : "Log in"}
          icon="server"
          disabled={!canSubmit}
          onPress={() => void submit()}
        />

        {register || registrationEnabled ? (
          <SecondaryButton
            title={register ? "Already have an account? Log in" : "Need an account? Register"}
            onPress={() => {
              setRegister(!register);
              setError(null);
              setNotice(null);
            }}
          />
        ) : null}

        <Text style={[styles.footnote, { color: palette.secondaryLabel }]}>
          Registration and login passwords are sent only to the server you choose. Use HTTPS outside your own network.
        </Text>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 60, paddingBottom: 40, gap: 20 },
  hero: { alignItems: "center", gap: 8, marginBottom: 4 },
  heroIcon: { width: 54, height: 54, borderRadius: 16, alignItems: "center", justifyContent: "center", marginBottom: 6 },
  brand: { fontSize: 34, fontWeight: "700" },
  tagline: { fontSize: 15, textAlign: "center", paddingHorizontal: 24 },
  localButtonWrap: { alignItems: "stretch" },
  localButton: { flexDirection: "row", alignItems: "center", justifyContent: "center", gap: 8, paddingVertical: 15 },
  message: { fontSize: 14, paddingHorizontal: 16 },
  footnote: { fontSize: 12, lineHeight: 17, paddingHorizontal: 16, textAlign: "center" },
});
