import Charts
import SwiftData
import SwiftUI

struct StockPositionDetailView: View {
    let holding: StockHolding
    @Query private var trades: [StockTrade]
    @AppStorage("ledgerly.hideFinancialAmounts") private var hidesFinancialAmounts = false

    init(holding: StockHolding) {
        self.holding = holding
        let id = holding.id
        _trades = Query(filter: #Predicate<StockTrade> { $0.holdingId == id }, sort: \.tradedAt, order: .reverse)
    }

    private var format: StockFormat { StockFormat(hidesAmounts: hidesFinancialAmounts) }

    var body: some View {
        List {
            if holding.isOpen {
                openSummary
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Realized gain").font(.subheadline).foregroundStyle(.secondary)
                        StockGainText(amount: StockTradeMath.realizedGain(trades: trades), fraction: nil, currency: holding.currency, format: format)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("You no longer hold any shares of this stock.")
                }
            }
            if holding.currency == "TWD", !hidesFinancialAmounts {
                Section { StockHistoryChart(symbol: holding.symbol, currency: holding.currency) }
            }
            if !hidesFinancialAmounts, !trades.isEmpty {
                Section("Trade prices") { priceChart }
            }
            Section("Details") {
                if holding.isOpen {
                    LabeledContent("Shares", value: format.shares(holding.quantity))
                    LabeledContent("Average cost", value: format.money(holding.averageCostMinor, holding.currency))
                    LabeledContent("Cost basis", value: format.money(holding.costBasisMinor, holding.currency))
                    if let change = holding.dayChangeValueMinor {
                        LabeledContent("Last session") {
                            StockGainText(amount: change, fraction: nil, currency: holding.currency, format: format)
                        }
                    }
                    LabeledContent("Realized gain") {
                        StockGainText(amount: StockTradeMath.realizedGain(trades: trades), fraction: nil, currency: holding.currency, format: format)
                    }
                }
                LabeledContent("Fees and tax paid", value: format.money(trades.reduce(0) { $0 + $1.feesMinor }, holding.currency))
            }
            if !trades.isEmpty {
                Section("Trades") {
                    ForEach(trades) { StockTradeRow(trade: $0, format: format) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(holding.symbol)
    }

    private var openSummary: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                if holding.name != holding.symbol {
                    Text(holding.name).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(format.money(holding.marketValueMinor, holding.currency))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                StockGainText(amount: holding.gainLossMinor, fraction: holding.returnFraction, currency: holding.currency, format: format)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.vertical, 4)
        } footer: {
            Text(priceNote)
        }
    }

    private var priceNote: String {
        let price = (Double(holding.currentPriceMinor) / 100).formatted(.currency(code: holding.currency).presentation(.isoCode))
        guard let date = holding.priceAsOf else { return "\(price) is your saved price." }
        return "\(price) close on \(date.formatted(date: .abbreviated, time: .omitted))."
    }

    private var priceChart: some View {
        Chart {
            ForEach(trades) { trade in
                let side = trade.side == "buy" ? "Buy" : "Sell"
                PointMark(x: .value("Date", trade.tradedDate, unit: .day), y: .value("Price", Double(trade.priceMinor) / 100))
                    .foregroundStyle(by: .value("Side", side))
                    .symbol(by: .value("Side", side))
                    .symbolSize(70)
            }
            if holding.isOpen {
                referenceLine("Avg cost", minor: holding.averageCostMinor, alignment: .leading)
                referenceLine("Price", minor: holding.currentPriceMinor, alignment: .trailing)
            }
        }
        .chartForegroundStyleScale(["Buy": StockChartColor.buy, "Sell": StockChartColor.sell])
        .chartSymbolScale(["Buy": BasicChartSymbolShape.circle, "Sell": BasicChartSymbolShape.triangle])
        .chartXScale(domain: chartDates)
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        .chartYScale(domain: chartPrices)
        .chartLegend(position: .bottom)
        .frame(height: 220)
        .padding(.vertical, 6)
        .accessibilityLabel("Trade prices over time. Every trade is listed below.")
    }

    /// Padded so edge points aren't clipped and a single trade still gets a usable range.
    private var chartDates: ClosedRange<Date> {
        let dates = trades.map(\.tradedDate)
        let first = dates.min() ?? Date(), last = dates.max() ?? Date()
        let padding = max(last.timeIntervalSince(first) * 0.06, 7 * 86_400)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }

    private var chartPrices: ClosedRange<Double> {
        let references = holding.isOpen ? [holding.averageCostMinor, holding.currentPriceMinor] : []
        let prices = (trades.map(\.priceMinor) + references).map { Double($0) / 100 }
        let low = prices.min() ?? 0, high = prices.max() ?? 0
        let padding = max((high - low) * 0.15, high * 0.02)
        return max(low - padding, 0)...(high + padding)
    }

    private func referenceLine(_ label: String, minor: Int, alignment: Alignment) -> some ChartContent {
        RuleMark(y: .value(label, Double(minor) / 100))
            .foregroundStyle(Color(.secondaryLabel))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .annotation(position: .top, alignment: alignment, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
    }
}

struct StockTradesView: View {
    @Query(sort: \StockTrade.tradedAt, order: .reverse) private var trades: [StockTrade]
    @AppStorage("ledgerly.hideFinancialAmounts") private var hidesFinancialAmounts = false
    @State private var side = "all"

    var body: some View {
        let format = StockFormat(hidesAmounts: hidesFinancialAmounts)
        List {
            Picker("Side", selection: $side) {
                Text("All").tag("all")
                Text("Buys").tag("buy")
                Text("Sells").tag("sell")
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            ForEach(months, id: \.month) { group in
                Section(group.month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(group.trades) { StockTradeRow(trade: $0, format: format) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Trades")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var months: [(month: Date, trades: [StockTrade])] {
        let shown = side == "all" ? trades : trades.filter { $0.side == side }
        let calendar = Calendar.current
        return Dictionary(grouping: shown) { calendar.dateInterval(of: .month, for: $0.tradedDate)?.start ?? $0.tradedDate }
            .map { (month: $0.key, trades: $0.value) }
            .sorted { $0.month > $1.month }
    }
}

struct StockTradeRow: View {
    let trade: StockTrade
    let format: StockFormat

    private var isBuy: Bool { trade.side == "buy" }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isBuy ? "arrow.down.left" : "arrow.up.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isBuy ? StockChartColor.buy : StockChartColor.sell)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(isBuy ? "Bought \(trade.symbol)" : "Sold \(trade.symbol)")
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(trade.tradedDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(format.money(StockTradeMath.gross(quantity: trade.quantity, priceMinor: trade.priceMinor), trade.currency))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("\(format.shares(trade.quantity)) × \(format.money(trade.priceMinor, trade.currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
