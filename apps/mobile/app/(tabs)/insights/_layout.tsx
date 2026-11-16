import { Stack } from "expo-router";

export const unstable_settings = { anchor: "index" };

export default function InsightsStack() {
  return (
    <Stack>
      <Stack.Screen name="index" />
      <Stack.Screen name="category/[category]" options={{ title: "Category", headerBackButtonDisplayMode: "minimal" }} />
      <Stack.Screen name="portfolio" options={{ title: "Portfolio", headerBackButtonDisplayMode: "minimal" }} />
      <Stack.Screen name="transaction/[id]" options={{ title: "Transaction", headerBackButtonDisplayMode: "minimal" }} />
    </Stack>
  );
}
