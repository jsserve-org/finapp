import { Ionicons } from "@expo/vector-icons";
import { Tabs } from "expo-router";
import { NativeTabs, Icon as NativeIcon, Label as NativeLabel } from "expo-router/unstable-native-tabs";
import { Platform } from "react-native";
import { useTheme } from "../../src/theme";

const tabs = [
  { name: "insights", label: "Insights", sf: "chart.bar.fill", ion: "bar-chart" },
  { name: "accounts", label: "Accounts", sf: "building.columns.fill", ion: "business" },
  { name: "add", label: "Add", sf: "plus.circle.fill", ion: "add-circle" },
  { name: "activity", label: "Activity", sf: "list.bullet", ion: "receipt" },
  { name: "settings", label: "Settings", sf: "gearshape.fill", ion: "settings-sharp" },
] as const;

export default function TabsLayout() {
  return Platform.OS === "ios" ? <NativeTabBar /> : <ClassicTabBar />;
}

function NativeTabBar() {
  const palette = useTheme();
  return (
    <NativeTabs tintColor={palette.blue}>
      {tabs.map((tab) => (
        <NativeTabs.Trigger key={tab.name} name={tab.name}>
          <NativeLabel>{tab.label}</NativeLabel>
          <NativeIcon sf={tab.sf} drawable="custom_android_drawable" />
        </NativeTabs.Trigger>
      ))}
    </NativeTabs>
  );
}

function ClassicTabBar() {
  const palette = useTheme();
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: palette.blue,
        tabBarInactiveTintColor: palette.secondaryLabel,
        tabBarStyle: { backgroundColor: palette.card, borderTopColor: palette.separator },
      }}
    >
      {tabs.map((tab) => (
        <Tabs.Screen
          key={tab.name}
          name={tab.name}
          options={{
            title: tab.label,
            tabBarIcon: ({ color, size }) => <Ionicons name={tab.ion} color={color} size={size} />,
          }}
        />
      ))}
    </Tabs>
  );
}
