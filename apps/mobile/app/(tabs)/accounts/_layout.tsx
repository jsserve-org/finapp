import { Stack } from "expo-router";

export default function AccountsStack() {
  return (
    <Stack>
      <Stack.Screen name="[id]" options={{ title: "Account", headerBackButtonDisplayMode: "minimal" }} />
      <Stack.Screen
        name="transaction/[id]"
        options={{ title: "Transaction", headerBackButtonDisplayMode: "minimal" }}
      />
    </Stack>
  );
}
