import { Stack } from "expo-router";

export default function InsightsStack() {
  return (
    <Stack>
      <Stack.Screen name="category/[category]" options={{ title: "Category", headerBackButtonDisplayMode: "minimal" }} />
      <Stack.Screen name="portfolio" options={{ title: "Portfolio", headerBackButtonDisplayMode: "minimal" }} />
      <Stack.Screen
        name="transaction/[id]"
        options={{ title: "Transaction", headerBackButtonDisplayMode: "minimal" }}
      />
    </Stack>
  );
}
