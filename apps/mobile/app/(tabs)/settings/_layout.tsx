import { Stack } from "expo-router";

export const unstable_settings = { anchor: "index" };

export default function SettingsStack() {
  return (
    <Stack>
      <Stack.Screen name="index" />
      <Stack.Screen name="server" options={{ title: "Server", headerBackButtonDisplayMode: "minimal" }} />
      <Stack.Screen name="api-keys" options={{ title: "API keys", headerBackButtonDisplayMode: "minimal" }} />
    </Stack>
  );
}
