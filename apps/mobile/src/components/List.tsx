import { Children, Fragment, isValidElement } from "react";
import { Pressable, StyleSheet, Text, View, type StyleProp, type ViewStyle } from "react-native";
import { useTheme } from "../theme";
import { Icon, type IconName } from "./Icon";
import { hairline } from "./Glass";

// iOS 26 grouped list metrics: larger, sentence-case section titles, generous
// rounded cards, and plain SF Symbols (no icon chips).
const metrics = {
  radius: 26,
  inset: 16,
  title: 17,
  subtitle: 15,
  value: 17,
  icon: 21,
  minRow: 50,
};

export function Screen({ children, style }: { children: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  const palette = useTheme();
  return <View style={[{ flex: 1, backgroundColor: palette.background }, style]}>{children}</View>;
}

export function Section({
  title,
  footer,
  children,
  style,
  headerAccessory,
}: {
  title?: string;
  footer?: string;
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
  headerAccessory?: React.ReactNode;
}) {
  const palette = useTheme();
  const items = Children.toArray(children).filter(Boolean);
  return (
    <View style={[{ gap: 8, marginBottom: 6 }, style]}>
      {(title || headerAccessory) && (
        <View style={styles.headerRow}>
          {title ? <Text style={[styles.header, { color: palette.label }]}>{title}</Text> : <View />}
          {headerAccessory}
        </View>
      )}
      <View style={{ borderRadius: metrics.radius, backgroundColor: palette.card, overflow: "hidden" }}>
        {items.map((child, index) => (
          <Fragment key={index}>
            {index > 0 && (
              <View
                style={{
                  height: hairline,
                  marginLeft: isValidElement(child) && (child.props as { icon?: unknown }).icon ? metrics.inset + 33 : metrics.inset,
                  backgroundColor: palette.separator,
                }}
              />
            )}
            {child}
          </Fragment>
        ))}
      </View>
      {footer ? <Text style={[styles.footer, { color: palette.secondaryLabel }]}>{footer}</Text> : null}
    </View>
  );
}

export function Row({
  title,
  subtitle,
  value,
  icon,
  iconColor,
  onPress,
  accessory,
  destructive,
  valueColor,
  disabled,
  trailing,
  showChevron = true,
  titleColor,
  strongValue,
}: {
  title: string;
  subtitle?: string;
  value?: string;
  icon?: IconName;
  iconColor?: string;
  onPress?: () => void;
  accessory?: React.ReactNode;
  destructive?: boolean;
  valueColor?: string;
  disabled?: boolean;
  trailing?: React.ReactNode;
  showChevron?: boolean;
  titleColor?: string;
  strongValue?: boolean;
}) {
  const palette = useTheme();
  const content = (
    <View style={[styles.row, disabled && { opacity: 0.45 }]}>
      {icon ? <Icon name={icon} size={metrics.icon} color={iconColor ?? palette.blue} /> : null}
      <View style={styles.grow}>
        <Text numberOfLines={1} style={[styles.title, subtitle != null && { fontWeight: "600" }, { color: titleColor ?? (destructive ? palette.red : palette.label) }]}>
          {title}
        </Text>
        {subtitle ? (
          <Text numberOfLines={1} style={[styles.subtitle, { color: palette.secondaryLabel }]}>
            {subtitle}
          </Text>
        ) : null}
      </View>
      {value ? (
        <Text numberOfLines={1} style={[styles.value, strongValue && { fontWeight: "600" }, { color: valueColor ?? palette.secondaryLabel }]}>
          {value}
        </Text>
      ) : null}
      {trailing}
      {accessory}
      {onPress && showChevron ? <Icon name="chevronRight" size={13} color={palette.tertiaryLabel} /> : null}
    </View>
  );

  if (!onPress) return content;
  return (
    <Pressable onPress={onPress} disabled={disabled} android_ripple={{ color: palette.fill }}>
      {({ pressed }) => <View style={pressed && { backgroundColor: palette.fill }}>{content}</View>}
    </Pressable>
  );
}

/** Label on the left, secondary value on the right (SwiftUI's LabeledContent). */
export function InfoRow({ label, value, valueColor }: { label: string; value: string; valueColor?: string }) {
  const palette = useTheme();
  return (
    <View style={[styles.row, styles.minRow]}>
      <Text style={[styles.title, { color: palette.label, flex: 1 }]}>{label}</Text>
      <Text style={[styles.value, { color: valueColor ?? palette.secondaryLabel }]} numberOfLines={2}>
        {value}
      </Text>
    </View>
  );
}

export function ValueRow({
  label,
  value,
  emphasis,
  valueColor,
}: {
  label: string;
  value: string;
  emphasis?: boolean;
  valueColor?: string;
}) {
  const palette = useTheme();
  return (
    <View style={[styles.row, styles.minRow]}>
      <Text style={[styles.title, { color: emphasis ? palette.secondaryLabel : palette.label, flex: 1 }]}>{label}</Text>
      <Text
        style={[
          styles.value,
          emphasis && { fontSize: 22, fontWeight: "700" },
          { color: valueColor ?? (emphasis ? palette.label : palette.secondaryLabel) },
        ]}
      >
        {value}
      </Text>
    </View>
  );
}

/** Label secondary, value semibold primary — the Insights summary row. */
export function StatRow({ label, value, valueColor }: { label: string; value: string; valueColor?: string }) {
  const palette = useTheme();
  return (
    <View style={[styles.row, styles.minRow]}>
      <Text style={[styles.title, { color: palette.secondaryLabel, flex: 1 }]}>{label}</Text>
      <Text style={[styles.value, { fontWeight: "600", color: valueColor ?? palette.label }]}>{value}</Text>
    </View>
  );
}

export function EmptyState({ icon, title, message, action }: { icon: IconName; title: string; message: string; action?: React.ReactNode }) {
  const palette = useTheme();
  return (
    <View style={styles.empty}>
      <Icon name={icon} size={40} color={palette.tertiaryLabel} weight="regular" />
      <Text style={[styles.emptyTitle, { color: palette.label }]}>{title}</Text>
      <Text style={[styles.emptyMessage, { color: palette.secondaryLabel }]}>{message}</Text>
      {action}
    </View>
  );
}

export function Badge({ text }: { text: string }) {
  const palette = useTheme();
  return (
    <Text style={{ color: palette.label, fontSize: metrics.value, fontWeight: "600", fontVariant: ["tabular-nums"] }}>
      {text}
    </Text>
  );
}

const styles = StyleSheet.create({
  headerRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: metrics.inset,
  },
  header: { fontSize: 20, fontWeight: "700", letterSpacing: -0.2 },
  footer: { fontSize: 13, lineHeight: 18, paddingHorizontal: metrics.inset },
  row: {
    flexDirection: "row",
    alignItems: "center",
    gap: 12,
    paddingHorizontal: metrics.inset,
    paddingVertical: 11,
    minHeight: metrics.minRow,
  },
  minRow: { minHeight: 44, paddingVertical: 10 },
  grow: { flex: 1, gap: 3 },
  title: { fontSize: metrics.title },
  subtitle: { fontSize: metrics.subtitle },
  value: { fontSize: metrics.value, fontVariant: ["tabular-nums"] },
  empty: { alignItems: "center", gap: 8, paddingVertical: 44, paddingHorizontal: 24 },
  emptyTitle: { fontSize: 17, fontWeight: "600", marginTop: 4 },
  emptyMessage: { fontSize: 14, lineHeight: 19, textAlign: "center" },
});
