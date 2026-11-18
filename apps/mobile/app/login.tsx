import * as SecureStore from "expo-secure-store";
import { useEffect, useState } from "react";
import { KeyboardAvoidingView, ScrollView, StyleSheet, View } from "react-native";
import { Button, Divider, HelperText, Text, TextInput, useTheme } from "react-native-paper";
import { SafeAreaView } from "react-native-safe-area-context";
import { authenticate, serverConfig } from "../src/api";
import { useSession } from "../src/session";

export default function Login() {
  const theme = useTheme();
  const session = useSession();
  // Start empty (or with the last server used) so a phone never silently targets the emulator's 10.0.2.2.
  const [apiUrl, setApiUrl] = useState<string>(process.env.EXPO_PUBLIC_API_URL ?? "");
  const [convexUrl, setConvexUrl] = useState<string>(process.env.EXPO_PUBLIC_CONVEX_URL ?? "");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [register, setRegister] = useState(false);
  const [error, setError] = useState<string>();
  const [notice, setNotice] = useState<string>();
  const [working, setWorking] = useState(false);
  const [registrationEnabled, setRegistrationEnabled] = useState(true);

  useEffect(() => {
    void Promise.all([SecureStore.getItemAsync("api-url"), SecureStore.getItemAsync("convex-url")]).then(([api, convex]) => {
      if (api) setApiUrl((current) => current || api);
      if (convex) setConvexUrl((current) => current || convex);
    });
  }, []);
  useEffect(() => {
    if (!apiUrl.trim()) return;
    const timer = setTimeout(() => {
      void serverConfig(apiUrl.trim()).then((config) => {
        setRegistrationEnabled(config.registrationEnabled);
        setConvexUrl((current) => current || config.convexUrl);
      }).catch(() => undefined);
    }, 400);
    return () => clearTimeout(timer);
  }, [apiUrl]);

  const submit = async () => {
    setWorking(true); setError(undefined); setNotice(undefined);
    try {
      const response = await authenticate(apiUrl.trim(), convexUrl.trim(), username, password, register);
      if (response) await session.login(response);
      else { setRegister(false); setNotice("Account created. Log in to continue."); }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Login failed");
    } finally { setWorking(false); }
  };
  const ready = !working && !!apiUrl.trim() && !!convexUrl.trim() && username.length >= 3 && password.length >= 10;

  return <SafeAreaView style={[styles.fill, { backgroundColor: theme.colors.background }]}>
    <KeyboardAvoidingView style={styles.fill} behavior="padding">
      <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
        <Text variant="labelLarge" style={{ color: theme.colors.primary }}>LEDGERLY</Text>
        <Text variant="displaySmall">{register ? "Create a sync account" : "Your money, on your device"}</Text>
        <Text variant="bodyLarge" style={{ color: theme.colors.onSurfaceVariant }}>{register ? "Create credentials for your self-hosted server." : "Start locally, or sign in to sync across devices."}</Text>

        {!register && <>
          <Button mode="contained" icon="cellphone" contentStyle={styles.big} onPress={() => void session.continueLocally()}>Continue on this phone</Button>
          <View style={styles.divider}><Divider style={styles.fill} /><Text variant="labelMedium" style={{ color: theme.colors.onSurfaceVariant }}>or connect a server</Text><Divider style={styles.fill} /></View>
        </>}

        <TextInput mode="outlined" label="API server" placeholder="http://192.168.1.10:3000" value={apiUrl} onChangeText={setApiUrl} autoCapitalize="none" autoCorrect={false} keyboardType="url" left={<TextInput.Icon icon="server-network" />} />
        <TextInput mode="outlined" label="Sync server" placeholder="http://192.168.1.10:3210" value={convexUrl} onChangeText={setConvexUrl} autoCapitalize="none" autoCorrect={false} keyboardType="url" left={<TextInput.Icon icon="sync" />} />
        <TextInput mode="outlined" label="Username" value={username} onChangeText={setUsername} autoCapitalize="none" autoCorrect={false} autoComplete="username" left={<TextInput.Icon icon="account-outline" />} />
        <View>
          <TextInput mode="outlined" label="Password" value={password} onChangeText={setPassword} secureTextEntry={!showPassword} autoComplete={register ? "new-password" : "current-password"}
            left={<TextInput.Icon icon="lock-outline" />} right={<TextInput.Icon icon={showPassword ? "eye-off" : "eye"} onPress={() => setShowPassword(!showPassword)} />} />
          <HelperText type={error ? "error" : "info"} visible={!!(error || notice || register)}>{error ?? notice ?? "At least 10 characters"}</HelperText>
        </View>

        <Button mode={register ? "contained" : "contained-tonal"} contentStyle={styles.big} loading={working} disabled={!ready} onPress={submit}>{register ? "Create account" : "Log in"}</Button>
        {(register || registrationEnabled) && <Button mode="text" onPress={() => { setRegister(!register); setError(undefined); setNotice(undefined); }}>{register ? "Already have an account? Log in" : "Need an account? Register"}</Button>}
      </ScrollView>
    </KeyboardAvoidingView>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  content: { flexGrow: 1, justifyContent: "center", padding: 24, gap: 12 },
  big: { paddingVertical: 8 },
  divider: { flexDirection: "row", alignItems: "center", gap: 12, marginVertical: 8 },
});
