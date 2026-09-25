import SwiftData
import SwiftUI

enum StockTradeMath {
    static func gross(quantity: Double, priceMinor: Int) -> Int {
        Int((quantity * Double(priceMinor)).rounded())
    }

    static func cashChange(side: String, quantity: Double, priceMinor: Int, feesMinor: Int) -> Int {
        let gross = gross(quantity: quantity, priceMinor: priceMinor)
        return side == "buy" ? -(gross + feesMinor) : gross - feesMinor
    }

    static func averageCost(oldQuantity: Double, oldAverageMinor: Int, boughtQuantity: Double, priceMinor: Int, feesMinor: Int) -> Int {
        let newQuantity = oldQuantity + boughtQuantity
        guard newQuantity > 0 else { return 0 }
        let total = oldQuantity * Double(oldAverageMinor) + boughtQuantity * Double(priceMinor) + Double(feesMinor)
        return Int((total / newQuantity).rounded())
    }
}

struct StockPortfolioView: View {
    @Query(sort: \StockHolding.symbol) private var holdings: [StockHolding]
    @Query(sort: \StockTrade.tradedAt, order: .reverse) private var trades: [StockTrade]

    private var totals: [(String, Int)] {
        Dictionary(grouping: holdings, by: \.currency)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.marketValueMinor }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        List {
            if holdings.isEmpty {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(trades.isEmpty ? "No investments synced" : "No positions synced")
                            .font(.headline)
                        Text(trades.isEmpty ? "Your investment automation will add holdings and trades here." : "Your imported trades appear below. Run a full history backfill so the automation can calculate positions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
            } else {
                Section("Portfolio value") {
                    ForEach(totals, id: \.0) { currency, amount in
                        LabeledContent(currency) { Text(stockMoney(amount, currency)).font(.title3.bold()) }
                    }
                }
                Section("Positions") {
                    ForEach(holdings) { holding in holdingRow(holding) }
                }
            }
            if !trades.isEmpty {
                Section("Recent trades") {
                    ForEach(trades.prefix(20)) { trade in tradeRow(trade) }
                }
            }
        }
        .navigationTitle("Investments")
    }

    private func holdingRow(_ holding: StockHolding) -> some View {
        HStack(spacing: 12) {
            Text(holding.symbol)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(holding.name).lineLimit(1)
                Text("\(holding.quantity.formatted()) shares · \(stockMoney(holding.currentPriceMinor, holding.currency))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(stockMoney(holding.marketValueMinor, holding.currency)).fontWeight(.semibold).lineLimit(1)
                Text(signedStockMoney(holding.gainLossMinor, holding.currency))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(holding.gainLossMinor >= 0 ? .green : .red)
            }
        }
        .padding(.vertical, 3)
    }

    private func tradeRow(_ trade: StockTrade) -> some View {
        HStack {
            Label(trade.side == "buy" ? "Bought \(trade.symbol)" : "Sold \(trade.symbol)", systemImage: trade.side == "buy" ? "arrow.down.left" : "arrow.up.right")
            Spacer()
            Text("\(trade.quantity.formatted()) × \(stockMoney(trade.priceMinor, trade.currency))")
                .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}

private func stockMoney(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
}

private func signedStockMoney(_ amount: Int, _ currency: String) -> String {
    let value = stockMoney(abs(amount), currency)
    return amount >= 0 ? "+\(value)" : "−\(value)"
}
