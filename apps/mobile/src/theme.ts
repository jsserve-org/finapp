import { useColorScheme } from "react-native";

export type Palette = {
  background: string;
  card: string;
  elevated: string;
  fill: string;
  separator: string;
  label: string;
  secondaryLabel: string;
  tertiaryLabel: string;
  blue: string;
  green: string;
  red: string;
  orange: string;
  glassTint: string | undefined;
};

const light: Palette = {
  background: "#F2F2F7",
  card: "#FFFFFF",
  elevated: "#FFFFFF",
  fill: "rgba(118, 118, 128, 0.12)",
  separator: "rgba(60, 60, 67, 0.29)",
  label: "#000000",
  secondaryLabel: "rgba(60, 60, 67, 0.6)",
  tertiaryLabel: "rgba(60, 60, 67, 0.3)",
  blue: "#007AFF",
  green: "#34C759",
  red: "#FF3B30",
  orange: "#FF9500",
  glassTint: undefined,
};

const dark: Palette = {
  background: "#000000",
  card: "#1C1C1E",
  elevated: "#2C2C2E",
  fill: "rgba(118, 118, 128, 0.24)",
  separator: "rgba(84, 84, 88, 0.65)",
  label: "#FFFFFF",
  secondaryLabel: "rgba(235, 235, 245, 0.6)",
  tertiaryLabel: "rgba(235, 235, 245, 0.3)",
  blue: "#0A84FF",
  green: "#30D158",
  red: "#FF453A",
  orange: "#FF9F0A",
  glassTint: undefined,
};

export function useTheme(): Palette {
  return useColorScheme() === "dark" ? dark : light;
}

export function amountColor(amountMinor: number, palette: Palette) {
  return amountMinor >= 0 ? palette.green : palette.red;
}

export const radii = { card: 22, row: 14, pill: 999 };
