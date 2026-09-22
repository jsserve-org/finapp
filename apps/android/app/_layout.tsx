import { Stack } from "expo-router";
import { useEffect } from "react";
import { initializeDatabase } from "../src/db";

export default function RootLayout() {
  useEffect(initializeDatabase, []);
  return <Stack screenOptions={{ headerShown: false }} />;
}
