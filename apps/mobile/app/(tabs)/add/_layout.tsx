import { Stack } from "expo-router";

export const unstable_settings = { anchor: "index" };

export default function AddStack() {
  return (
    <Stack>
      <Stack.Screen name="index" />
    </Stack>
  );
}
