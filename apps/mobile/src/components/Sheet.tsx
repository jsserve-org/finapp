import { Stack } from "expo-router";
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTheme } from "../theme";

/**
 * Modal sheet scaffold: native header, scrollable grouped content, and a
 * pinned action bar that mirrors the iOS app's `safeAreaInset` buttons.
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
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
        >
          {children}
        </ScrollView>
        {footer ? (
          <View style={[styles.footer, { backgroundColor: palette.card, borderColor: palette.separator, paddingBottom: insets.bottom + 14 }]}>
            {footer}
          </View>
        ) : null}
      </KeyboardAvoidingView>
    </View>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 20, paddingBottom: 28 },
  footer: { paddingHorizontal: 16, paddingTop: 12, borderTopWidth: StyleSheet.hairlineWidth },
});
