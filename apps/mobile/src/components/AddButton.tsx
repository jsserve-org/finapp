import { useRouter } from "expo-router";
import { useState } from "react";
import { ActionSheetIOS, Modal, Platform, Pressable, StyleSheet, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTheme } from "../theme";
import { tap } from "../haptics";
import { GlassSurface } from "./Glass";
import { Icon, type IconName } from "./Icon";

type Flow = { key: string; title: string; icon: IconName; href: string; tone: "blue" | "green" | "red" };

const flows: Flow[] = [
  { key: "quick", title: "Quick spend", icon: "quickSpend", href: "/add/quick-spend", tone: "blue" },
  { key: "in", title: "Add money", icon: "addCircle", href: "/add/money?direction=in", tone: "green" },
  { key: "out", title: "Spend money", icon: "minusCircle", href: "/add/money?direction=out", tone: "red" },
  { key: "transfer", title: "Transfer money", icon: "transfer", href: "/add/transfer", tone: "blue" },
  { key: "bill", title: "Recurring bill", icon: "bill", href: "/add/bill", tone: "blue" },
];

export function AddButton() {
  const router = useRouter();
  const palette = useTheme();
  const insets = useSafeAreaInsets();
  const [sheet, setSheet] = useState(false);

  const open = (href: string) => {
    setSheet(false);
    router.push(href as never);
  };

  const showMenu = () => {
    tap();
    if (Platform.OS === "ios") {
      const options = ["Cancel", ...flows.map((flow) => flow.title)];
      ActionSheetIOS.showActionSheetWithOptions(
        { options, cancelButtonIndex: 0, title: "Add" },
        (index) => {
          if (index > 0) open(flows[index - 1].href);
        },
      );
      return;
    }
    setSheet(true);
  };

  return (
    <>
      <View pointerEvents="box-none" style={[styles.container, { bottom: insets.bottom + 76 }]}>
        <Pressable onPress={showMenu} accessibilityLabel="Add" accessibilityRole="button">
          {({ pressed }) => (
            <GlassSurface radius={29} interactive style={[styles.button, pressed && { opacity: 0.75 }]} tintColor={palette.blue}>
              <Icon name="plus" size={24} color={palette.blue} weight="bold" />
            </GlassSurface>
          )}
        </Pressable>
      </View>
      <Modal visible={sheet} transparent animationType="fade" onRequestClose={() => setSheet(false)}>
        <Pressable style={styles.backdrop} onPress={() => setSheet(false)}>
          <View style={[styles.sheet, { backgroundColor: palette.elevated, paddingBottom: insets.bottom + 16 }]}>
            {flows.map((flow) => (
              <Pressable key={flow.key} onPress={() => open(flow.href)} style={styles.sheetRow}>
                <Icon
                  name={flow.icon}
                  size={20}
                  color={flow.tone === "red" ? palette.red : flow.tone === "green" ? palette.green : palette.blue}
                />
                <Text style={[styles.sheetText, { color: palette.label }]}>{flow.title}</Text>
              </Pressable>
            ))}
          </View>
        </Pressable>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  container: { position: "absolute", right: 18 },
  button: { width: 58, height: 58, alignItems: "center", justifyContent: "center", shadowColor: "#000", shadowOpacity: 0.18, shadowRadius: 12, shadowOffset: { width: 0, height: 6 } },
  backdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.35)", justifyContent: "flex-end" },
  sheet: { borderTopLeftRadius: 22, borderTopRightRadius: 22, paddingTop: 12, paddingHorizontal: 8 },
  sheetRow: { flexDirection: "row", alignItems: "center", gap: 14, paddingVertical: 15, paddingHorizontal: 14 },
  sheetText: { fontSize: 18 },
});
