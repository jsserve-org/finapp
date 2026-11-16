import { GlassView, isLiquidGlassAvailable } from "expo-glass-effect";
import { Platform, StyleSheet, View, type StyleProp, type ViewStyle } from "react-native";
import { useTheme } from "../theme";

const liquidGlass = Platform.OS === "ios" && isLiquidGlassAvailable();

/**
 * iOS 26 renders a real Liquid Glass surface. Older iOS versions and Android
 * fall back to the same rounded card the native app uses with materials.
 */
export function GlassSurface({
  children,
  style,
  tintColor,
  interactive,
  radius = 22,
}: {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
  tintColor?: string;
  interactive?: boolean;
  radius?: number;
}) {
  const palette = useTheme();
  if (liquidGlass) {
    return (
      <GlassView
        glassEffectStyle="regular"
        tintColor={tintColor}
        isInteractive={interactive}
        style={[{ borderRadius: radius }, style]}
      >
        {children}
      </GlassView>
    );
  }
  return (
    <View style={[{ borderRadius: radius, backgroundColor: palette.card, overflow: "hidden" }, style]}>{children}</View>
  );
}

export const glassAvailable = liquidGlass;

export const hairline = StyleSheet.hairlineWidth;
