import { useRouter } from "expo-router";
import { useState } from "react";
import { Pressable, ScrollView, StyleSheet, Text, TextInput } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { authenticate } from "../src/api";
import { useSession } from "../src/session";

export default function Login() {
  const router = useRouter(); const session = useSession();
  const [apiUrl, setApiUrl] = useState(process.env.EXPO_PUBLIC_API_URL ?? "http://10.0.2.2:3000");
  const [convexUrl, setConvexUrl] = useState(process.env.EXPO_PUBLIC_CONVEX_URL ?? "http://10.0.2.2:3210");
  const [username, setUsername] = useState(""); const [password, setPassword] = useState("");
  const [register, setRegister] = useState(false); const [error, setError] = useState<string>(); const [working, setWorking] = useState(false);
  const submit = async () => { setWorking(true); setError(undefined); try { const response = await authenticate(apiUrl, convexUrl, username, password, register); if (response) { await session.login(response); router.replace("/"); } else { setRegister(false); setError("Account created. Log in to continue."); } } catch (e) { setError(e instanceof Error ? e.message : "Login failed"); } finally { setWorking(false); } };
  return <SafeAreaView style={styles.safe}><ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <Text style={styles.logo}>◒</Text><Text style={styles.title}>{register ? "Create account" : "Welcome back"}</Text><Text style={styles.muted}>Connect securely to your Ledgerly server.</Text>
    <TextInput value={apiUrl} onChangeText={setApiUrl} placeholder="API endpoint" placeholderTextColor="#73847D" autoCapitalize="none" keyboardType="url" style={styles.input} />
    <TextInput value={convexUrl} onChangeText={setConvexUrl} placeholder="Convex endpoint" placeholderTextColor="#73847D" autoCapitalize="none" keyboardType="url" style={styles.input} />
    <TextInput value={username} onChangeText={setUsername} placeholder="Username" placeholderTextColor="#73847D" autoCapitalize="none" autoComplete="username" style={styles.input} />
    <TextInput value={password} onChangeText={setPassword} placeholder="Password (10+ characters)" placeholderTextColor="#73847D" secureTextEntry autoComplete={register ? "new-password" : "current-password"} style={styles.input} />
    {error && <Text style={styles.error}>{error}</Text>}
    <Pressable style={[styles.primary, (working || username.length < 3 || password.length < 10) && styles.disabled]} disabled={working || username.length < 3 || password.length < 10} onPress={submit}><Text style={styles.primaryText}>{working ? "Connecting…" : register ? "Create account" : "Log in"}</Text></Pressable>
    <Pressable onPress={() => { setRegister(!register); setError(undefined); }}><Text style={styles.link}>{register ? "Already have an account? Log in" : "Need an account? Register"}</Text></Pressable>
  </ScrollView></SafeAreaView>;
}
const styles = StyleSheet.create({ safe: { flex: 1, backgroundColor: "#071712" }, content: { flexGrow: 1, justifyContent: "center", padding: 28, gap: 12 }, logo: { color: "#70D6AD", fontSize: 64 }, title: { color: "#F4FFF9", fontSize: 36, fontWeight: "700", marginTop: 10 }, muted: { color: "#7D9B8F", marginBottom: 18 }, input: { backgroundColor: "#10241D", color: "#F4FFF9", padding: 16, borderRadius: 15, fontSize: 16 }, primary: { backgroundColor: "#70D6AD", padding: 16, borderRadius: 15, alignItems: "center", marginTop: 8 }, disabled: { opacity: 0.45 }, primaryText: { color: "#071712", fontWeight: "800", fontSize: 16 }, link: { color: "#70D6AD", textAlign: "center", marginTop: 10 }, error: { color: "#FF918A" } });
