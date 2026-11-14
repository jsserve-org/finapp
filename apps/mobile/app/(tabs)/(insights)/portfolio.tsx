import { useMemo } from "react";
import { ScrollView, StyleSheet, Text } from "react-native";
import { cachedHoldings, cachedTrades } from "../../../src/db";
import { formatDate, formatMoney } from "../../../src/format";
import { portfolioTotals } from "../../../src/insights";
import { useCacheVersion, useHiddenAmounts } from "../../../src/store";
import { useTheme } from "../../../src/theme";
import { EmptyState, Row, Section, Screen } from "../../../src/components/List";

export default function PortfolioScreen() {
  const palette = useTheme();
  const version = useCacheVersion();
  const [hidden] = useHiddenAmounts();
  const holdings = useMemo(() => cachedHoldings(), [version]);
  const trades = useMemo(() => cachedTrades().sort((a, b) => b.tradedAt.localeCompare(a.tradedAt)).slice(0, 20), [version]);
  const totals = useMemo(() => portfolioTotals(holdings), [holdings]);
  const shown = (amount: number, currency: string) => (hidden ? "••••" : formatMoney(amount, currency));

  return (
    <Screen>
      <ScrollView contentContainerStyle={styles.content}>
        <Section title="Portfolio">
          {totals.length === 0 ? (
            <EmptyState icon="investment" title="No holdings yet" message="Stock holdings sync from your server when trades are recorded." />
          ) : (
            totals.map((total) => <Row key={total.currency} title={total.currency} value={shown(total.amount, total.currency)} valueColor={palette.label} />)
          )}
        </Section>

        <Section title="Holdings" footer="Current value uses the latest price stored on the server.">
          {holdings.length === 0 ? (
            <EmptyState icon="investment" title="Nothing to show" message="Holdings appear after the first trade syncs." />
          ) : (
            holdings.map((holding) => {
              const marketValue = Math.round(holding.quantity * holding.currentPriceMinor);
              const cost = Math.round(holding.quantity * holding.averageCostMinor);
              const gain = marketValue - cost;
              return (
                <Row
                  key={holding.id}
                  icon="investment"
                  title={`${holding.symbol} · ${holding.quantity}`}
                  subtitle={`${holding.name} · avg ${formatMoney(holding.averageCostMinor, holding.currency)}`}
                  value={`${shown(marketValue, holding.currency)} (${gain >= 0 ? "+" : ""}${shown(gain, holding.currency)})`}
                  valueColor={gain >= 0 ? palette.green : palette.red}
                />
              );
            })
          )}
        </Section>

        {trades.length > 0 ? (
          <Section title="Recent trades">
            {trades.map((trade) => (
              <Row
                key={trade.id}
                icon="transfer"
                title={`${trade.side === "buy" ? "Buy" : "Sell"} ${trade.symbol}`}
                subtitle={`${trade.quantity} @ ${formatMoney(trade.priceMinor, trade.currency)} · ${formatDate(trade.tradedAt, "short")}`}
                value={formatMoney(Math.round(trade.quantity * trade.priceMinor), trade.currency)}
              />
            ))}
          </Section>
        ) : null}
        <Text style={[styles.hint, { color: palette.secondaryLabel }]}>
          Trades are recorded through the API or agents; this build shows the synced portfolio.
        </Text>
      </ScrollView>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { padding: 16, gap: 22, paddingBottom: 60 },
  hint: { fontSize: 13, paddingHorizontal: 16 },
});
