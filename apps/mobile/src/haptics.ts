import * as Haptics from "expo-haptics";
import { Platform } from "react-native";

// Haptics are a no-op on devices without a Taptic Engine.
const enabled = Platform.OS === "ios";

export const tap = () => {
  if (enabled) void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => undefined);
};

export const success = () => {
  if (enabled) void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => undefined);
};

export const warning = () => {
  if (enabled) void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning).catch(() => undefined);
};

export const select = () => {
  if (enabled) void Haptics.selectionAsync().catch(() => undefined);
};
