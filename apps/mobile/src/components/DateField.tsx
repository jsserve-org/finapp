import DateTimePicker from "@react-native-community/datetimepicker";
import { useState } from "react";
import { Modal, Platform, Pressable, StyleSheet, Text, View, useColorScheme } from "react-native";
import { formatDate } from "../format";
import { useTheme } from "../theme";
import { Icon } from "./Icon";

export function DateField({
  value,
  onChange,
  label = "Date",
}: {
  value: Date;
  onChange: (date: Date) => void;
  label?: string;
}) {
  const palette = useTheme();
  const scheme = useColorScheme();
  const [visible, setVisible] = useState(false);
  const [draft, setDraft] = useState(value);

  return (
    <>
      <Pressable
        onPress={() => {
          setDraft(value);
          setVisible(true);
        }}
        style={styles.field}
      >
        <Text style={[styles.label, { color: palette.label }]}>{label}</Text>
        <View style={{ flex: 1 }} />
        <Text style={{ color: palette.secondaryLabel, fontSize: 17 }}>{formatDate(value)}</Text>
        <Icon name="chevronRight" size={12} color={palette.tertiaryLabel} />
      </Pressable>
      <Modal visible={visible} transparent animationType="fade" onRequestClose={() => setVisible(false)}>
        <Pressable style={styles.backdrop} onPress={() => setVisible(false)}>
          <Pressable style={[styles.sheet, { backgroundColor: palette.elevated }]} onPress={() => {}}>
            <Text style={[styles.title, { color: palette.label }]}>{label}</Text>
            <DateTimePicker
              value={draft}
              mode="date"
              display={Platform.OS === "ios" ? "inline" : "calendar"}
              themeVariant={scheme === "dark" ? "dark" : "light"}
              onChange={(_, date) => {
                if (date) {
                  setDraft(date);
                  if (Platform.OS !== "ios") {
                    onChange(date);
                    setVisible(false);
                  }
                }
              }}
            />
            {Platform.OS === "ios" ? (
              <Pressable
                style={[styles.done, { backgroundColor: palette.blue }]}
                onPress={() => {
                  onChange(draft);
                  setVisible(false);
                }}
              >
                <Text style={{ color: "#FFFFFF", fontSize: 17, fontWeight: "600" }}>Done</Text>
              </Pressable>
            ) : null}
          </Pressable>
        </Pressable>
      </Modal>
    </>
  );
}

const styles = StyleSheet.create({
  field: { flexDirection: "row", alignItems: "center", gap: 10, paddingHorizontal: 16, paddingVertical: 12, minHeight: 50 },
  label: { fontSize: 17, minWidth: 92 },
  backdrop: { flex: 1, backgroundColor: "rgba(0,0,0,0.35)", justifyContent: "flex-end" },
  sheet: { borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 16, paddingBottom: 28, gap: 10 },
  title: { fontSize: 17, fontWeight: "600", textAlign: "center" },
  done: { paddingVertical: 13, borderRadius: 13, alignItems: "center" },
});
