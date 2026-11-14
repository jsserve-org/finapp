import { Ionicons } from "@expo/vector-icons";
import { Tabs } from "expo-router";
import { NativeTabs, Icon as NativeIcon, Label as NativeLabel } from "expo-router/unstable-native-tabs";
import { Platform, StyleSheet, View } from "react-native";
import { AddButton } from "../../src/components/AddButton";
import { useTheme } from "../../src/theme";

export default function TabsLayout() {
  return (
    <View style={styles.container}>
      {Platform.OS === "ios" ? <NativeTabBar /> : <ClassicTabBar />}
      <AddButton />
    </View>
  );
}

function NativeTabBar() {
  const palette = useTheme();
  return (
    <NativeTabs tintColor={palette.blue}>
      <NativeTabs.Trigger name="(insights)">
        <NativeLabel>Insights</NativeLabel>
        <NativeIcon sf="chart.bar.fill" drawable="custom_android_drawable" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(accounts)">
        <NativeLabel>Accounts</NativeLabel>
        <NativeIcon sf="building.columns.fill" drawable="custom_android_drawable" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="(activity)">
        <NativeLabel>Activity</NativeLabel>
        <NativeIcon sf="list.bullet" drawable="custom_android_drawable" />
      </NativeTabs.Trigger>
      <NativeTabs.Trigger name="settings">
        <NativeLabel>Settings</NativeLabel>
        <NativeIcon sf="gearshape.fill" drawable="custom_android_drawable" />
      </NativeTabs.Trigger>
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
      <Tabs.Screen
        name="(insights)"
        options={{
          title: "Insights",
          tabBarIcon: ({ color, size }) => <Ionicons name="bar-chart" color={color} size={size} />,
        }}
      />
      <Tabs.Screen
        name="(accounts)"
        options={{
          title: "Accounts",
          tabBarIcon: ({ color, size }) => <Ionicons name="business" color={color} size={size} />,
        }}
      />
      <Tabs.Screen
        name="(activity)"
        options={{
          title: "Activity",
          tabBarIcon: ({ color, size }) => <Ionicons name="receipt" color={color} size={size} />,
        }}
      />
      <Tabs.Screen
        name="settings"
        options={{
          title: "Settings",
          tabBarIcon: ({ color, size }) => <Ionicons name="settings-sharp" color={color} size={size} />,
        }}
      />
    </Tabs>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1 },
});
