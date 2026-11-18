import * as SecureStore from "expo-secure-store";
import { useEffect, useState } from "react";
import { StyleSheet, View } from "react-native";
import { Avatar, Button, Card, List, Text } from "react-native-paper";
import { useSession } from "../../src/session";
import { Screen } from "../../src/ui";

export default function Settings() {
  const { localOnly, configureSync, logout } = useSession();
  const [server, setServer] = useState<string | null>(null);
  useEffect(() => { void SecureStore.getItemAsync("api-url").then(setServer); }, []);

  return <Screen title="Settings">
    <View style={styles.profile}>
      <Avatar.Icon size={72} icon={localOnly ? "cellphone" : "account-sync-outline"} />
      <Text variant="headlineSmall">{localOnly ? "On this phone" : "Synced"}</Text>
      <Text variant="bodyMedium" style={styles.center}>{localOnly ? "Your data stays on this phone until you turn on sync." : "Your data syncs with your Ledgerly server."}</Text>
    </View>
    <Card mode="contained">
      <List.Item title="Storage" description={localOnly ? "Local only" : "This phone and your server"} left={(props) => <List.Icon {...props} icon="database-outline" />} />
      {!localOnly && <List.Item title="Server" description={server ?? "Unknown"} left={(props) => <List.Icon {...props} icon="server-network" />} />}
    </Card>
    {localOnly
      ? <Button mode="contained" icon="cloud-sync-outline" onPress={() => void configureSync()}>Set up sync</Button>
      : <Button mode="contained-tonal" icon="logout" onPress={() => void logout()}>Log out</Button>}
  </Screen>;
}

const styles = StyleSheet.create({
  profile: { alignItems: "center", gap: 8, paddingVertical: 8 },
  center: { textAlign: "center" },
});
