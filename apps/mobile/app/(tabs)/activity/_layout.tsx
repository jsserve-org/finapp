import { Stack } from "expo-router";

export const unstable_settings = { anchor: "index" };

export default function ActivityStack() {
  return (
    <Stack>
      <Stack.Screen name="index" />
      <Stack.Screen name="transaction/[id]" options={{ title: "Transaction", headerBackButtonDisplayMode: "minimal" }} />
      <Stack.Screen name="bill/[id]" options={{ title: "Recurring bill", headerBackButtonDisplayMode: "minimal" }} />
    </Stack>
  );
}
