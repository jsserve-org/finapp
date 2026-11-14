import { Stack } from "expo-router";

export default function SettingsStack() {
  return (
    <Stack>
      <Stack.Screen name="server" options={{ title: "Server", headerBackButtonDisplayMode: "minimal" }} />
      <Stack.Screen name="api-keys" options={{ title: "API keys", headerBackButtonDisplayMode: "minimal" }} />
    </Stack>
  );
}
