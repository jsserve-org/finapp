import { StyleSheet, Text, View } from "react-native";
import { useTheme } from "../theme";

export function StepHeader({ current, total, instruction }: { current: number; total: number; instruction: string }) {
  const palette = useTheme();
  return (
    <View style={styles.block}>
      <Text style={[styles.step, { color: palette.secondaryLabel }]}>{`Step ${current} of ${total}`}</Text>
      <View style={[styles.track, { backgroundColor: palette.fill }]}>
        <View style={[styles.fill, { backgroundColor: palette.blue, width: `${(current / total) * 100}%` }]} />
      </View>
      <Text style={[styles.instruction, { color: palette.label }]}>{instruction}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  block: { gap: 8, paddingVertical: 10 },
  step: { fontSize: 13, fontWeight: "600" },
  track: { height: 4, borderRadius: 2, overflow: "hidden" },
  fill: { height: 4, borderRadius: 2 },
  instruction: { fontSize: 20, fontWeight: "600" },
});
