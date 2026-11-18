import { CommonActions } from "@react-navigation/native";
import { Tabs } from "expo-router";
import { BottomNavigation, Icon } from "react-native-paper";

const tabs = [
  { name: "insights", title: "Insights", icon: "chart-bar" },
  { name: "accounts", title: "Accounts", icon: "bank" },
  { name: "add", title: "Add", icon: "plus-circle" },
  { name: "activity", title: "Activity", icon: "receipt-text" },
  { name: "settings", title: "Settings", icon: "cog" },
];

export default function TabLayout() {
  return <Tabs initialRouteName="insights" screenOptions={{ headerShown: false }}
    tabBar={({ navigation, state, descriptors, insets }) => {
      const routes = tabs.flatMap(tab => state.routes.filter(route => route.name === tab.name));
      const index = Math.max(0, routes.findIndex(route => route.key === state.routes[state.index].key));
      return <BottomNavigation.Bar navigationState={{ index, routes }} safeAreaInsets={insets}
        onTabPress={({ route, preventDefault }) => {
          const event = navigation.emit({ type: "tabPress", target: route.key, canPreventDefault: true });
          if (event.defaultPrevented) preventDefault();
          else navigation.dispatch({ ...CommonActions.navigate(route.name, route.params), target: state.key });
        }}
        renderIcon={({ route, focused, color }) => descriptors[route.key].options.tabBarIcon?.({ focused, color, size: 24 }) ?? null}
        getLabelText={({ route }) => descriptors[route.key].options.title}
      />;
    }}>
    <Tabs.Screen name="index" options={{ href: null }} />
    {tabs.map(tab => <Tabs.Screen key={tab.name} name={tab.name} options={{ title: tab.title,
      tabBarIcon: ({ color, size }) => <Icon source={tab.icon} color={color} size={size} />,
    }} />)}
  </Tabs>;
}
