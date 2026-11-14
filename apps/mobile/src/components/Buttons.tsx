import { Pressable, StyleSheet, Text, View } from "react-native";
import { useTheme } from "../theme";
import { Icon, type IconName } from "./Icon";

const tones = (color: string) => ({ backgroundColor: color });

export function PrimaryButton({
  title,
  icon,
  onPress,
  disabled,
  tone = "blue",
}: {
  title: string;
  icon?: IconName;
  onPress: () => void;
  disabled?: boolean;
  tone?: "blue" | "red" | "green";
}) {
  const palette = useTheme();
  const color = tone === "red" ? palette.red : tone === "green" ? palette.green : palette.blue;
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      style={({ pressed }) => [
        styles.primary,
        tones(color),
        (disabled || pressed) && { opacity: disabled ? 0.4 : 0.82 },
      ]}
    >
      {icon ? <Icon name={icon} size={17} color="#FFFFFF" weight="bold" /> : null}
      <Text style={styles.primaryText}>{title}</Text>
    </Pressable>
  );
}

export function SecondaryButton({
  title,
  icon,
  onPress,
  tone = "blue",
  disabled,
}: {
  title: string;
  icon?: IconName;
  onPress: () => void;
  tone?: "blue" | "red" | "green";
  disabled?: boolean;
}) {
  const palette = useTheme();
  const color = tone === "red" ? palette.red : tone === "green" ? palette.green : palette.blue;
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      style={({ pressed }) => [styles.secondary, { backgroundColor: palette.card }, (disabled || pressed) && { opacity: 0.6 }]}
    >
      {icon ? <Icon name={icon} size={17} color={color} weight="semibold" /> : null}
      <Text style={[styles.secondaryText, { color }]}>{title}</Text>
    </Pressable>
  );
}

export function DestructiveButton({ title, onPress, icon = "trash" }: { title: string; onPress: () => void; icon?: IconName }) {
  const palette = useTheme();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      style={({ pressed }) => [styles.secondary, { backgroundColor: palette.card }, pressed && { opacity: 0.6 }]}
    >
      <Icon name={icon} size={17} color={palette.red} weight="semibold" />
      <Text style={[styles.secondaryText, { color: palette.red }]}>{title}</Text>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  primary: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    paddingVertical: 15,
    borderRadius: 14,
  },
  primaryText: { color: "#FFFFFF", fontSize: 17, fontWeight: "600" },
  secondary: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 8,
    paddingVertical: 14,
    borderRadius: 14,
  },
  secondaryText: { fontSize: 17, fontWeight: "600" },
});
