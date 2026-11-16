/** Money is always stored as integer minor units, like the native app and the API. */

const cachedFormatters = new Map<string, Intl.NumberFormat>();

export function formatMoney(amountMinor: number, currency: string): string {
  const key = currency.toUpperCase();
  let formatter = cachedFormatters.get(key);
  if (!formatter) {
    try {
      formatter = new Intl.NumberFormat(undefined, {
        style: "currency",
        currency: key,
        currencyDisplay: "code",
      });
    } catch {
      formatter = new Intl.NumberFormat(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
    }
    cachedFormatters.set(key, formatter);
  }
  return formatter.format(amountMinor / 100);
}

/** Parses "12.34", "-4", "0,50" into minor units. Returns null when the text is not a valid amount. */
export function parseMinorUnits(input: string): number | null {
  const text = input.trim().replace(/,/g, ".");
  if (!/^[+-]?(?:[0-9]+(?:\.[0-9]{0,2})?|\.[0-9]{1,2})$/.test(text)) return null;
  const value = Number(text);
  if (!Number.isFinite(value)) return null;
  const minor = Math.round(value * 100);
  return Number.isSafeInteger(minor) ? minor : null;
}

export function moneyInputFromMinor(amountMinor: number): string {
  return (Math.abs(amountMinor) / 100).toFixed(2);
}

export function parseISODate(value: string | undefined | null): Date | null {
  if (!value) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

export function formatDate(value: string | Date | undefined | null, style: "short" | "medium" | "month" = "medium"): string {
  const date = value instanceof Date ? value : parseISODate(value);
  if (!date) return "Unknown date";
  if (style === "month") return date.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  return date.toLocaleDateString(undefined, style === "short" ? { month: "short", day: "numeric" } : { month: "short", day: "numeric", year: "numeric" });
}

export function formatMonthShort(date: Date): string {
  return date.toLocaleDateString(undefined, { month: "short", year: "numeric" });
}

export function startOfMonth(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

export function addMonths(date: Date, months: number): Date {
  return new Date(date.getFullYear(), date.getMonth() + months, 1);
}

export function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

/** Reference epoch used by the Convex sync layer for recurring bill dates. */
const convexEpoch = Date.UTC(2001, 0, 1);

export function recurringDateToISO(value: unknown): string | null {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(convexEpoch + value * 1000).toISOString();
  }
  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }
  return null;
}

export function isoNow(): string {
  return new Date().toISOString();
}

export function defaultCurrency(): string {
  try {
    const code = new Intl.NumberFormat().resolvedOptions().currency;
    return code && /^[A-Z]{3}$/.test(code) ? code : "TWD";
  } catch {
    return "TWD";
  }
}

export const supportedCurrencies = [
  { code: "TWD", name: "New Taiwan dollar" },
  { code: "USD", name: "US dollar" },
  { code: "JPY", name: "Japanese yen" },
  { code: "PHP", name: "Philippine peso" },
  { code: "EUR", name: "Euro" },
  { code: "GBP", name: "British pound" },
  { code: "CNY", name: "Chinese yuan" },
  { code: "HKD", name: "Hong Kong dollar" },
  { code: "SGD", name: "Singapore dollar" },
  { code: "KRW", name: "South Korean won" },
  { code: "AUD", name: "Australian dollar" },
  { code: "CAD", name: "Canadian dollar" },
  { code: "THB", name: "Thai baht" },
  { code: "MYR", name: "Malaysian ringgit" },
  { code: "VND", name: "Vietnamese dong" },
  { code: "INR", name: "Indian rupee" },
  { code: "IDR", name: "Indonesian rupiah" },
];
