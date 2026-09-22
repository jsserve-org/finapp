import { Ionicons } from "@expo/vector-icons";
import { StyleSheet, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

const settings = [
  { icon: "person-outline" as const, label: "Profile" },
  { icon: "sync-outline" as const, label: "Sync settings" },
  { icon: "shield-checkmark-outline" as const, label: "Security" },
  { icon: "notifications-outline" as const, label: "Notifications" },
];

export default function Settings() {
  return <SafeAreaView style={styles.safe}><View style={styles.content}>
    <Text style={styles.title}>Settings</Text>
    <View style={styles.avatar}><Ionicons name="person" color="#70D6AD" size={34} /></View>
    <Text style={styles.name}>Ledgerly</Text><Text style={styles.muted}>Your preferences and connection details</Text>
    <View style={styles.card}>{settings.map((item, index) => <View key={item.label} style={[styles.row, index < settings.length - 1 && styles.divider]}><Ionicons name={item.icon} color="#70D6AD" size={21} /><Text style={styles.label}>{item.label}</Text><Ionicons name="chevron-forward" color="#73847D" size={19} /></View>)}</View>
  </View></SafeAreaView>;
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: "#071712" }, content: { padding: 20, alignItems: "center" }, title: { color: "#F4FFF9", fontSize: 22, fontWeight: "700", marginBottom: 28 }, avatar: { width: 76, height: 76, borderRadius: 26, backgroundColor: "#18382D", alignItems: "center", justifyContent: "center" }, name: { color: "#F4FFF9", fontSize: 24, fontWeight: "700", marginTop: 14 }, muted: { color: "#7D9B8F", marginTop: 5, textAlign: "center" }, card: { width: "100%", backgroundColor: "#10241D", borderRadius: 22, paddingHorizontal: 18, marginTop: 28 }, row: { height: 62, flexDirection: "row", alignItems: "center", gap: 13 }, divider: { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: "#294239" }, label: { color: "#F2FFF9", fontSize: 16, flex: 1 },
});
