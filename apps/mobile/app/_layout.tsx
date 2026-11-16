import { Stack, useRouter, useSegments } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useEffect } from "react";
import { Platform } from "react-native";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { initializeDatabase } from "../src/db";
import { SessionProvider, useSession } from "../src/session";
import { SyncProvider } from "../src/sync";

initializeDatabase();

export default function RootLayout() {
  return (
    <SafeAreaProvider>
      <SessionProvider>
        <SyncProvider>
          <RootNavigator />
        </SyncProvider>
      </SessionProvider>
      <StatusBar style="auto" />
    </SafeAreaProvider>
  );
}

function RootNavigator() {
  const { canUseApp, loading } = useSession();
  const segments = useSegments();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    const onLogin = segments[0] === "login";
    if (!canUseApp && !onLogin) router.replace("/login");
    if (canUseApp && onLogin) router.replace("/insights");
  }, [canUseApp, loading, router, segments]);

  return (
    <Stack screenOptions={{ headerBackButtonDisplayMode: "minimal" }}>
      <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="login" />
      <Stack.Screen name="add/money" options={sheetOptions("Spend money")} />
      <Stack.Screen name="add/transfer" options={sheetOptions("Transfer")} />
      <Stack.Screen name="add/quick-spend" options={sheetOptions("Quick spend")} />
      <Stack.Screen name="add/bill" options={sheetOptions("Recurring bill")} />
      <Stack.Screen name="account/new" options={sheetOptions("New account")} />
      <Stack.Screen name="account/[id]/edit" options={sheetOptions("Edit account")} />
      <Stack.Screen name="bill/[id]" options={sheetOptions("Recurring bill")} />
      <Stack.Screen name="settings/api-keys" options={{ title: "API keys" }} />
      <Stack.Screen name="settings/server" options={{ title: "Server" }} />
    </Stack>
  );
}

function sheetOptions(title: string) {
  return {
    title,
    presentation: Platform.OS === "ios" ? ("modal" as const) : ("card" as const),
    headerLargeTitle: false,
  };
}
