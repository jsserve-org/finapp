import { Children, Fragment } from "react";
import { Pressable, StyleSheet, Text, View, type StyleProp, type ViewStyle } from "react-native";
import { useTheme, type Palette } from "../theme";
import { Icon, type IconName } from "./Icon";
import { hairline } from "./Glass";

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
    <View style={[{ gap: 7 }, style]}>
      {(title || headerAccessory) && (
        <View style={styles.headerRow}>
          {title ? <Text style={[styles.header, { color: palette.secondaryLabel }]}>{title.toUpperCase()}</Text> : <View />}
          {headerAccessory}
        </View>
      )}
      <View style={{ borderRadius: 22, backgroundColor: palette.card, overflow: "hidden" }}>
        {items.map((child, index) => (
          <Fragment key={index}>
            {index > 0 && <View style={{ height: hairline, marginLeft: 16, backgroundColor: palette.separator }} />}
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
}) {
  const palette = useTheme();
  const content = (
    <View style={[styles.row, disabled && { opacity: 0.45 }]}>
      {icon ? (
        <View style={[styles.iconWrap, { backgroundColor: palette.fill }]}>
          <Icon name={icon} size={17} color={iconColor ?? palette.blue} />
        </View>
      ) : null}
      <View style={styles.grow}>
        <Text numberOfLines={1} style={[styles.title, { color: destructive ? palette.red : palette.label }]}>
          {title}
        </Text>
        {subtitle ? (
          <Text numberOfLines={1} style={[styles.subtitle, { color: palette.secondaryLabel }]}>
            {subtitle}
          </Text>
        ) : null}
      </View>
      {value ? (
        <Text numberOfLines={1} style={[styles.value, { color: valueColor ?? palette.secondaryLabel }]}>
          {value}
        </Text>
      ) : null}
      {accessory}
      {onPress ? <Icon name="chevronRight" size={13} color={palette.tertiaryLabel} /> : null}
    </View>
  );

  if (!onPress) return content;
  return (
    <Pressable onPress={onPress} disabled={disabled} android_ripple={{ color: palette.fill }}>
      {({ pressed }) => <View style={pressed && { backgroundColor: palette.fill }}>{content}</View>}
    </Pressable>
  );
}

export function InfoRow({ label, value, valueColor }: { label: string; value: string; valueColor?: string }) {
  const palette = useTheme();
  return (
    <View style={styles.row}>
      <Text style={[styles.title, { color: palette.label, flex: 1 }]}>{label}</Text>
      <Text style={[styles.value, { color: valueColor ?? palette.secondaryLabel }]}>{value}</Text>
    </View>
  );
}

export function EmptyState({ icon, title, message, action }: { icon: IconName; title: string; message: string; action?: React.ReactNode }) {
  const palette = useTheme();
  return (
    <View style={styles.empty}>
      <Icon name={icon} size={38} color={palette.tertiaryLabel} weight="regular" />
      <Text style={[styles.emptyTitle, { color: palette.label }]}>{title}</Text>
      <Text style={[styles.emptyMessage, { color: palette.secondaryLabel }]}>{message}</Text>
      {action}
    </View>
  );
}

export function Badge({ text, palette }: { text: string; palette: Palette }) {
  return (
    <View style={[styles.badge, { backgroundColor: palette.fill }]}>
      <Text style={{ color: palette.label, fontSize: 15, fontWeight: "600", fontVariant: ["tabular-nums"] }}>{text}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  headerRow: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", paddingHorizontal: 16 },
  header: { fontSize: 13, fontWeight: "600", letterSpacing: 0.3 },
  footer: { fontSize: 13, lineHeight: 18, paddingHorizontal: 16 },
  row: { flexDirection: "row", alignItems: "center", gap: 12, paddingHorizontal: 16, paddingVertical: 11, minHeight: 48 },
  iconWrap: { width: 30, height: 30, borderRadius: 8, alignItems: "center", justifyContent: "center" },
  grow: { flex: 1, gap: 2 },
  title: { fontSize: 17 },
  subtitle: { fontSize: 13 },
  value: { fontSize: 17, fontVariant: ["tabular-nums"] },
  empty: { alignItems: "center", gap: 8, paddingVertical: 44, paddingHorizontal: 24 },
  emptyTitle: { fontSize: 17, fontWeight: "600", marginTop: 4 },
  emptyMessage: { fontSize: 14, lineHeight: 19, textAlign: "center" },
  badge: { paddingHorizontal: 10, paddingVertical: 4, borderRadius: 8 },
});
