import { useRouter } from "expo-router";
import { useEffect, useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, TextInput } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { authenticate, serverConfig } from "../src/api";
import { useSession } from "../src/session";

export default function Login() {
  const router = useRouter(); const session = useSession();
  const [apiUrl, setApiUrl] = useState(process.env.EXPO_PUBLIC_API_URL ?? "http://10.0.2.2:3000");
  const [convexUrl, setConvexUrl] = useState(process.env.EXPO_PUBLIC_CONVEX_URL ?? "http://10.0.2.2:3210");
  const [username, setUsername] = useState(""); const [password, setPassword] = useState("");
  const [register, setRegister] = useState(false); const [error, setError] = useState<string>(); const [working, setWorking] = useState(false);
  const [registrationEnabled, setRegistrationEnabled] = useState(true);
  useEffect(() => { const timer = setTimeout(() => { void serverConfig(apiUrl).then((config) => { setRegistrationEnabled(config.registrationEnabled); if (convexUrl === "http://10.0.2.2:3210") setConvexUrl(config.convexUrl); }).catch(() => undefined); }, 400); return () => clearTimeout(timer); }, [apiUrl]);
  const submit = async () => { setWorking(true); setError(undefined); try { const response = await authenticate(apiUrl, convexUrl, username, password, register); if (response) { await session.login(response); router.replace("/"); } else { setRegister(false); setError("Account created. Log in to continue."); } } catch (e) { setError(e instanceof Error ? e.message : "Login failed"); } finally { setWorking(false); } };
  return <SafeAreaView style={styles.safe}><ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <Text style={styles.brand}>LEDGERLY</Text><Text style={styles.title}>{register ? "Create a sync account" : "Your money, on your device"}</Text><Text style={styles.muted}>{register ? "Create credentials for your self-hosted server." : "Start locally, or sign in to sync across devices."}</Text>
    {!register && <><Pressable style={styles.primary} onPress={() => void session.continueLocally()}><Text style={styles.primaryText}>Continue on this phone</Text></Pressable><Text style={styles.divider}>OR CONNECT A SERVER</Text></>}
    <TextInput value={apiUrl} onChangeText={setApiUrl} placeholder="API endpoint" placeholderTextColor="#73847D" autoCapitalize="none" keyboardType="url" style={styles.input} />
    <TextInput value={convexUrl} onChangeText={setConvexUrl} placeholder="Convex endpoint" placeholderTextColor="#73847D" autoCapitalize="none" keyboardType="url" style={styles.input} />
    <TextInput value={username} onChangeText={setUsername} placeholder="Username" placeholderTextColor="#73847D" autoCapitalize="none" autoComplete="username" style={styles.input} />
    <TextInput value={password} onChangeText={setPassword} placeholder="Password (10+ characters)" placeholderTextColor="#73847D" secureTextEntry autoComplete={register ? "new-password" : "current-password"} style={styles.input} />
    {error && <Text style={styles.error}>{error}</Text>}
    <Pressable style={[styles.primary, (working || username.length < 3 || password.length < 10) && styles.disabled]} disabled={working || username.length < 3 || password.length < 10} onPress={submit}><Text style={styles.primaryText}>{working ? "Connecting…" : register ? "Create account" : "Log in"}</Text></Pressable>
    {(register || registrationEnabled) && <Pressable onPress={() => { setRegister(!register); setError(undefined); }}><Text style={styles.link}>{register ? "Already have an account? Log in" : "Need an account? Register"}</Text></Pressable>}
  </ScrollView></SafeAreaView>;
}
const styles = StyleSheet.create({ safe: { flex: 1, backgroundColor: "#0B0C0F" }, content: { flexGrow: 1, justifyContent: "center", padding: 28, gap: 12 }, brand: { color: "#89909A", fontSize: 12, fontWeight: "800", letterSpacing: 2 }, title: { color: "#F5F6F8", fontSize: 36, fontWeight: "700", marginTop: 10 }, muted: { color: "#9298A2", marginBottom: 18 }, divider: { color: "#626873", fontSize: 10, letterSpacing: 1.5, textAlign: "center", marginVertical: 10 }, input: { backgroundColor: "#17191F", color: "#F5F6F8", padding: 16, borderRadius: 15, fontSize: 16 }, primary: { backgroundColor: "#7A9FFF", padding: 16, borderRadius: 15, alignItems: "center", marginTop: 8 }, disabled: { opacity: 0.45 }, primaryText: { color: "#0B0C0F", fontWeight: "800", fontSize: 16 }, link: { color: "#9CB7FF", textAlign: "center", marginTop: 10 }, error: { color: "#FF918A" } });
