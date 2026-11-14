import { Stack } from "expo-router";
import { Platform, ScrollView, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTheme } from "../theme";

/**
 * Modal sheet scaffold: native header, grouped form content, and the primary
 * action at the end of the form.
 *
 * The action lives inside the scroll view on purpose: iOS 26 page-sheet modals
 * do not deliver keyboard notifications to React Native, so a pinned bar would
 * sit under the keyboard. Inline content scrolls above it instead.
 */
export function SheetScreen({
  title,
  children,
  footer,
  headerLeft,
  headerRight,
}: {
  title: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
  headerLeft?: React.ReactNode;
  headerRight?: React.ReactNode;
}) {
  const palette = useTheme();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ flex: 1, backgroundColor: palette.background }}>
      <Stack.Screen
        options={{
          title,
          presentation: Platform.OS === "ios" ? "modal" : "card",
          headerBackVisible: false,
          headerLeft: headerLeft ? () => headerLeft : undefined,
          headerRight: headerRight ? () => headerRight : undefined,
        }}
      />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 32 }]}
        keyboardShouldPersistTaps="handled"
        keyboardDismissMode="interactive"
        automaticallyAdjustKeyboardInsets
      >
        {children}
        {footer ? <View style={styles.footer}>{footer}</View> : null}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 20, gap: 20 },
  footer: { paddingTop: 4 },
});
