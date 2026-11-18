import { Stack } from "expo-router";
import { useState } from "react";
import { initializeDatabase } from "../src/db";
import { SessionProvider, useSession } from "../src/session";
import { ThemeProvider } from "../src/ui";

export default function RootLayout() {
  useState(() => { initializeDatabase(); return true; });
  return <ThemeProvider><SessionProvider><Routes /></SessionProvider></ThemeProvider>;
}

function Routes() {
  const { token, localOnly, loading } = useSession();
  if (loading) return null;
  const signedIn = !!token || localOnly;
  return <Stack screenOptions={{ headerShown: false }}>
    <Stack.Protected guard={signedIn}><Stack.Screen name="(tabs)" /></Stack.Protected>
    <Stack.Protected guard={!signedIn}><Stack.Screen name="login" /></Stack.Protected>
  </Stack>;
}
