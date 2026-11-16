import { Stack, useRouter } from "expo-router";
import { ScrollView, StyleSheet, View } from "react-native";
import { Section } from "../../../src/components/List";
import { Row } from "../../../src/components/List";
import { Screen } from "../../../src/components/List";
import { useTheme } from "../../../src/theme";
import { tap } from "../../../src/haptics";

const actions = [
  { href: "/add/quick-spend", title: "Quick spend", icon: "quickSpend", tone: "blue" },
  { href: "/add/money?direction=in", title: "Add money", icon: "addCircle", tone: "green" },
  { href: "/add/money?direction=out", title: "Spend money", icon: "minusCircle", tone: "red" },
  { href: "/add/transfer", title: "Transfer money", icon: "transfer", tone: "blue" },
  { href: "/add/bill", title: "Recurring bill", icon: "bill", tone: "blue" },
] as const;

export default function AddScreen() {
  const palette = useTheme();
  const router = useRouter();
  return (
    <Screen>
      <Stack.Screen options={{ title: "Add", headerLargeTitle: true }} />
      <ScrollView contentInsetAdjustmentBehavior="automatic" contentContainerStyle={styles.content}>
        <Section
          footer="Expenses are one-time transactions. Recurring bills repeat on a schedule and never move money on their own."
        >
          {actions.map((action) => (
            <Row
              key={action.href}
              icon={action.icon}
              iconColor={action.tone === "red" ? palette.red : action.tone === "green" ? palette.green : palette.blue}
              title={action.title}
              onPress={() => {
                tap();
                router.push(action.href as never);
              }}
            />
          ))}
        </Section>
        <View style={{ height: 24 }} />
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, paddingTop: 8 },
});
