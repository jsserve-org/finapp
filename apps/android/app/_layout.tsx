import { Ionicons } from "@expo/vector-icons";
import { Redirect, Stack, Tabs, useSegments } from "expo-router";
import { useEffect } from "react";
import { initializeDatabase } from "../src/db";
import { SessionProvider, useSession } from "../src/session";

export default function RootLayout() {
  useEffect(initializeDatabase, []);
  return <SessionProvider><AuthenticatedTabs /></SessionProvider>;
}

function AuthenticatedTabs() {
  const { token, localOnly, loading } = useSession();
  const segments = useSegments();
  if (loading) return null;
  if (!token && !localOnly) return segments[0] === "login" ? <Stack screenOptions={{ headerShown: false }}><Stack.Screen name="login" /></Stack> : <Redirect href="/login" />;
  if (segments[0] === "login") return <Redirect href="/" />;
  return <Tabs screenOptions={{
    headerShown: false,
    sceneStyle: { backgroundColor: "#0B0C0F" },
    tabBarActiveTintColor: "#9CB7FF",
    tabBarInactiveTintColor: "#777E89",
    tabBarLabelStyle: { fontSize: 11, fontWeight: "600", marginTop: 2 },
    tabBarStyle: {
      backgroundColor: "#12141A",
      borderTopColor: "#292D36",
      height: 70,
      paddingTop: 8,
      paddingBottom: 8,
    },
  }}>
    <Tabs.Screen name="login" options={{ href: null }} />
    <Tabs.Screen name="index" options={{
      title: "Overview",
      tabBarIcon: ({ color, size, focused }) => <Ionicons name={focused ? "grid" : "grid-outline"} color={color} size={size} />,
    }} />
    <Tabs.Screen name="accounts" options={{
      title: "Accounts",
      tabBarIcon: ({ color, size, focused }) => <Ionicons name={focused ? "business" : "business-outline"} color={color} size={size} />,
    }} />
    <Tabs.Screen name="insights" options={{
      title: "Insights",
      tabBarIcon: ({ color, size, focused }) => <Ionicons name={focused ? "bar-chart" : "bar-chart-outline"} color={color} size={size} />,
    }} />
    <Tabs.Screen name="activity" options={{
      title: "Activity",
      tabBarIcon: ({ color, size, focused }) => <Ionicons name={focused ? "receipt" : "receipt-outline"} color={color} size={size} />,
    }} />
    <Tabs.Screen name="settings" options={{
      title: "Settings",
      tabBarIcon: ({ color, size, focused }) => <Ionicons name={focused ? "person-circle" : "person-circle-outline"} color={color} size={size} />,
    }} />
  </Tabs>;
}
