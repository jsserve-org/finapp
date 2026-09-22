import { Ionicons } from "@expo/vector-icons";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import { useSession } from "../src/session";

const settings = [
  { icon: "person-outline" as const, label: "Profile" },
  { icon: "sync-outline" as const, label: "Sync settings" },
  { icon: "shield-checkmark-outline" as const, label: "Security" },
  { icon: "notifications-outline" as const, label: "Notifications" },
];

export default function Settings() {
  const { localOnly, configureSync, logout } = useSession();
  return <SafeAreaView style={styles.safe}><View style={styles.content}>
    <Text style={styles.title}>Settings</Text>
    <View style={styles.avatar}><Ionicons name="person" color="#9CB7FF" size={34} /></View>
    <Text style={styles.name}>{localOnly ? "On this phone" : "Ledgerly"}</Text><Text style={styles.muted}>{localOnly ? "Your data stays local until you enable sync." : "Your preferences and connection details"}</Text>
    <View style={styles.card}>{settings.map((item, index) => <View key={item.label} style={[styles.row, index < settings.length - 1 && styles.divider]}><Ionicons name={item.icon} color="#9CB7FF" size={21} /><Text style={styles.label}>{item.label}</Text><Ionicons name="chevron-forward" color="#777E89" size={19} /></View>)}</View>
    <Pressable onPress={() => void (localOnly ? configureSync() : logout())}><Text style={localOnly ? styles.sync : styles.logout}>{localOnly ? "Set up sync" : "Log out"}</Text></Pressable>
  </View></SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#0B0C0F" }, content: { padding: 20, alignItems: "center" }, title: { color: "#F5F6F8", fontSize: 22, fontWeight: "700", marginBottom: 28 }, avatar: { width: 76, height: 76, borderRadius: 26, backgroundColor: "#222630", alignItems: "center", justifyContent: "center" }, name: { color: "#F5F6F8", fontSize: 24, fontWeight: "700", marginTop: 14 }, muted: { color: "#9298A2", marginTop: 5, textAlign: "center" }, card: { width: "100%", backgroundColor: "#17191F", borderRadius: 22, paddingHorizontal: 18, marginTop: 28 }, row: { height: 62, flexDirection: "row", alignItems: "center", gap: 13 }, divider: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "#292D36" }, label: { color: "#F5F6F8", fontSize: 16, flex: 1 },
  logout: { color: "#FF918A", fontSize: 16, fontWeight: "700", marginTop: 28 },
  sync: { color: "#9CB7FF", fontSize: 16, fontWeight: "700", marginTop: 28 },
});
