import { Ionicons } from "@expo/vector-icons";
import { SymbolView, type SFSymbol, type SymbolWeight } from "expo-symbols";
import type { ComponentProps } from "react";

type IoniconName = ComponentProps<typeof Ionicons>["name"];

const iconMap = {
  insights: { sf: "chart.bar.fill", ion: "bar-chart" },
  accounts: { sf: "building.columns.fill", ion: "business" },
  activity: { sf: "list.bullet", ion: "receipt" },
  settings: { sf: "gearshape.fill", ion: "settings-sharp" },
  account: { sf: "building.columns.fill", ion: "business" },
  checking: { sf: "building.columns.fill", ion: "business" },
  savings: { sf: "banknote.fill", ion: "cash" },
  credit: { sf: "creditcard.fill", ion: "card" },
  sharedCredit: { sf: "creditcard.fill", ion: "card" },
  investment: { sf: "chart.line.uptrend.xyaxis", ion: "trending-up" },
  cash: { sf: "wallet.bifold.fill", ion: "wallet" },
  plus: { sf: "plus", ion: "add" },
  minus: { sf: "minus", ion: "remove" },
  addCircle: { sf: "plus.circle.fill", ion: "add-circle" },
  minusCircle: { sf: "minus.circle.fill", ion: "remove-circle" },
  arrowDown: { sf: "arrow.down.circle.fill", ion: "arrow-down-circle" },
  arrowUp: { sf: "arrow.up.circle.fill", ion: "arrow-up-circle" },
  transfer: { sf: "arrow.left.arrow.right.circle.fill", ion: "swap-horizontal" },
  quickSpend: { sf: "bolt.fill", ion: "flash" },
  bill: { sf: "repeat", ion: "repeat" },
  calendar: { sf: "calendar", ion: "calendar" },
  chevronRight: { sf: "chevron.right", ion: "chevron-forward" },
  ellipsis: { sf: "ellipsis.circle", ion: "ellipsis-horizontal-circle" },
  edit: { sf: "pencil.circle.fill", ion: "pencil" },
  link: { sf: "link", ion: "link" },
  clock: { sf: "clock.fill", ion: "time" },
  portfolio: { sf: "chart.line.uptrend.xyaxis", ion: "trending-up" },
  chevronDown: { sf: "chevron.down", ion: "chevron-down" },
  checkCircle: { sf: "checkmark.circle.fill", ion: "checkmark-circle" },
  circle: { sf: "circle", ion: "ellipse-outline" },
  checkmark: { sf: "checkmark", ion: "checkmark" },
  eye: { sf: "eye", ion: "eye" },
  eyeSlash: { sf: "eye.slash", ion: "eye-off" },
  trash: { sf: "trash", ion: "trash" },
  server: { sf: "server.rack", ion: "server" },
  key: { sf: "key.fill", ion: "key" },
  lock: { sf: "lock.shield.fill", ion: "shield-checkmark" },
  photo: { sf: "photo.on.rectangle", ion: "image" },
  upload: { sf: "square.and.arrow.up", ion: "share-outline" },
  download: { sf: "square.and.arrow.down", ion: "download-outline" },
  warning: { sf: "exclamationmark.triangle.fill", ion: "warning" },
  search: { sf: "magnifyingglass", ion: "search" },
  close: { sf: "xmark", ion: "close" },
  pieChart: { sf: "chart.pie.fill", ion: "pie-chart" },
  food: { sf: "fork.knife", ion: "restaurant" },
  groceries: { sf: "cart.fill", ion: "cart" },
  housing: { sf: "house.fill", ion: "home" },
  transport: { sf: "car.fill", ion: "car" },
  shopping: { sf: "bag.fill", ion: "bag-handle" },
  health: { sf: "cross.case.fill", ion: "medkit" },
  travel: { sf: "airplane", ion: "airplane" },
  education: { sf: "book.fill", ion: "book" },
  bills: { sf: "doc.text.fill", ion: "document-text" },
  subscriptions: { sf: "play.rectangle.fill", ion: "play-circle" },
  transferCategory: { sf: "arrow.left.arrow.right", ion: "swap-horizontal" },
  info: { sf: "info.circle.fill", ion: "information-circle" },
  person: { sf: "person.crop.circle.fill", ion: "person-circle" },
  iphone: { sf: "iphone", ion: "phone-portrait" },
} satisfies Record<string, { sf: SFSymbol; ion: IoniconName }>;

export type IconName = keyof typeof iconMap;

export function Icon({
  name,
  size = 18,
  color = "#007AFF",
  weight = "semibold",
}: {
  name: IconName;
  size?: number;
  color?: string;
  weight?: SymbolWeight;
}) {
  const entry = iconMap[name];
  return (
    <SymbolView
      name={entry.sf}
      size={size}
      tintColor={color}
      weight={weight}
      resizeMode="scaleAspectFit"
      fallback={<Ionicons name={entry.ion} size={size} color={color} />}
    />
  );
}

/** Payment icons follow the native app's keyword matching. */
export function paymentIconFor(title: string, category: string | null | undefined, amountMinor: number): IconName {
  if (amountMinor > 0) return "arrowDown";
  const text = `${category ?? ""} ${title}`.toLowerCase();
  const matches: [string[], IconName][] = [
    [["subscription", "netflix", "spotify", "icloud"], "subscriptions"],
    [["food", "dining", "restaurant", "coffee"], "food"],
    [["grocery", "supermarket"], "groceries"],
    [["housing", "rent", "mortgage"], "housing"],
    [["transport", "uber", "taxi", "fuel"], "transport"],
    [["shopping", "retail"], "shopping"],
    [["health", "medical", "pharmacy"], "health"],
    [["travel", "flight", "hotel"], "travel"],
    [["education", "school"], "education"],
    [["bill", "utility", "telecom"], "bills"],
    [["screenshot", "import"], "photo"],
  ];
  return matches.find(([words]) => words.some((word) => text.includes(word)))?.[1] ?? "credit";
}

export function accountIcon(kind: string): IconName {
  if (kind === "savings") return "savings";
  if (kind === "credit" || kind === "sharedCredit") return "credit";
  if (kind === "investment") return "investment";
  if (kind === "cash") return "cash";
  return "account";
}
