import { Stack } from "expo-router";
import { BlurView } from "expo-blur";
import { useEffect, useState } from "react";
import { Keyboard, Platform, ScrollView, StyleSheet, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTheme } from "../theme";

/**
 * Modal sheet scaffold: native header, scrollable grouped content, and a
 * pinned action bar that mirrors the iOS app's `safeAreaInset` buttons.
 * The footer lifts above the keyboard because KeyboardAvoidingView does not
 * resize a page-sheet modal on iOS 26.
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
  const [keyboardHeight, setKeyboardHeight] = useState(0);

  useEffect(() => {
    const showEvent = Platform.OS === "ios" ? "keyboardWillShow" : "keyboardDidShow";
    const hideEvent = Platform.OS === "ios" ? "keyboardWillHide" : "keyboardDidHide";
    const show = Keyboard.addListener(showEvent, (event) => setKeyboardHeight(event.endCoordinates.height));
    const hide = Keyboard.addListener(hideEvent, () => setKeyboardHeight(0));
    return () => {
      show.remove();
      hide.remove();
    };
  }, []);

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
      <View style={{ flex: 1, paddingBottom: keyboardHeight > 0 ? Math.max(0, keyboardHeight - insets.bottom) : 0 }}>
        <ScrollView
          contentInsetAdjustmentBehavior="automatic"
          contentContainerStyle={styles.content}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="interactive"
          automaticallyAdjustKeyboardInsets
        >
          {children}
        </ScrollView>
        {footer ? (
          <View style={[styles.footer, { borderColor: palette.separator, paddingBottom: keyboardHeight > 0 ? 14 : insets.bottom + 14 }]}>
            {Platform.OS === "ios" ? (
              <BlurView intensity={90} tint="systemChromeMaterial" style={StyleSheet.absoluteFill} />
            ) : (
              <View style={[StyleSheet.absoluteFill, { backgroundColor: palette.card }]} />
            )}
            {footer}
          </View>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 20, gap: 20, paddingBottom: 28 },
  footer: { paddingHorizontal: 16, paddingTop: 12, borderTopWidth: StyleSheet.hairlineWidth },
});
