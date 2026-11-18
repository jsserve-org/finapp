import { useMaterial3Theme } from "@pchmn/expo-material3-theme";
import { StatusBar } from "expo-status-bar";
import { createContext, useContext, useMemo, useState, type ReactElement, type ReactNode } from "react";
import { MaterialCommunityIcons } from "@expo/vector-icons";
import { readSetting, writeSetting } from "./db";
import { ScrollView, StyleSheet, useColorScheme, View, type RefreshControlProps, type StyleProp, type ViewStyle } from "react-native";
import { Appbar, Avatar, MD3DarkTheme, MD3LightTheme, PaperProvider, useTheme } from "react-native-paper";

/** Ledgerly's icon blue, used when the phone has no Material You wallpaper colours. */
const brandColor = "#3274ED";

/** Material 3 theme from the phone's wallpaper colours (Android 12+), following light/dark mode. */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const dark = useColorScheme() === "dark";
  const { theme } = useMaterial3Theme({ fallbackSourceColor: brandColor });
  const paper = dark ? { ...MD3DarkTheme, colors: theme.dark } : { ...MD3LightTheme, colors: theme.light };
  return <PaperProvider theme={paper} settings={{ icon: ({ name, color, size }) => <MaterialCommunityIcons name={name in MaterialCommunityIcons.glyphMap ? name as keyof typeof MaterialCommunityIcons.glyphMap : "help-circle-outline"} color={color} size={size} /> }}><AmountsProvider><StatusBar style={dark ? "light" : "dark"} />{children}</AmountsProvider></PaperProvider>;
}

export const money = (minor: number, currency: string) => new Intl.NumberFormat(undefined, { style: "currency", currency }).format(minor / 100);

/** A tab page: large top app bar, then scrolling content. */
export function Screen({ title, actions, overlay, refreshControl, children }: { title: string; actions?: ReactNode; overlay?: ReactNode; refreshControl?: ReactElement<RefreshControlProps>; children: ReactNode }) {
  const theme = useTheme();
  return <View style={[styles.fill, { backgroundColor: theme.colors.background }]}>
    <Appbar.Header mode="large" style={{ backgroundColor: theme.colors.background }}>
      <Appbar.Content title={title} />
      {actions}
    </Appbar.Header>
    <ScrollView contentContainerStyle={styles.content} refreshControl={refreshControl}>{children}</ScrollView>
    {overlay}
  </View>;
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  content: { paddingHorizontal: 16, paddingBottom: 24, gap: 16 },
});

/** Leading icon for list rows, in tonal container colours. */
export function RowIcon({ icon, style }: { icon: string; style?: StyleProp<ViewStyle> }) {
  const theme = useTheme();
  return <Avatar.Icon size={40} icon={icon} color={theme.colors.onPrimaryContainer} style={[{ backgroundColor: theme.colors.primaryContainer }, style]} />;
}

const AmountsContext = createContext<{ hidden: boolean; toggle(): void; money(minor: number, currency: string): string } | null>(null);
function AmountsProvider({ children }: { children: ReactNode }) {
  const [hidden, setHidden] = useState(() => readSetting("hide-amounts") === "true");
  const value = useMemo(() => ({ hidden, toggle: () => {
    writeSetting("hide-amounts", String(!hidden));
    setHidden(!hidden);
  }, money: (minor: number, currency: string) => hidden ? "••••" : money(minor, currency) }), [hidden]);
  return <AmountsContext.Provider value={value}>{children}</AmountsContext.Provider>;
}
export function useAmounts() {
  const value = useContext(AmountsContext);
  if (!value) throw new Error("AmountsProvider missing");
  return value;
}
export function useMoneyColors() {
  const theme = useTheme();
  return { income: theme.dark ? "#81C995" : "#137333", expense: theme.colors.error };
}
