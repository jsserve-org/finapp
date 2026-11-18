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

    /// Replays one holding's trades with the importer's average-cost rules. Sell fees and tax reduce the gain.
    static func realizedGain(trades: [StockTrade]) -> Int {
        let ordered = trades.sorted {
            if $0.tradedDate != $1.tradedDate { return $0.tradedDate < $1.tradedDate }
            // Statements have no execution time, so same-day buys fund same-day sells.
            return $0.side == "buy" && $1.side != "buy"
        }
        var quantity = 0.0
        var average = 0
        var realized = 0
        for trade in ordered {
            if trade.side == "buy" {
                average = averageCost(oldQuantity: quantity, oldAverageMinor: average, boughtQuantity: trade.quantity, priceMinor: trade.priceMinor, feesMinor: trade.feesMinor)
                quantity += trade.quantity
            } else {
                let sold = min(trade.quantity, quantity)
                guard sold > 0 else { continue }
                realized += gross(quantity: sold, priceMinor: trade.priceMinor) - gross(quantity: sold, priceMinor: average) - trade.feesMinor
                quantity -= sold
                if quantity == 0 { average = 0 }
            }
        }
        return realized
    }
}

extension StockTrade {
    var tradedDate: Date {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: tradedAt) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: tradedAt) ?? .distantPast
    }
}

struct StockPortfolioSummary: Equatable {
    let valueMinor, costMinor, realizedMinor: Int
    let dayChangeMinor: Int?
    let priceAsOf: Date?
    let unquotedCount: Int

    init(holdings: [StockHolding], trades: [StockTrade]) {
        let open = holdings.filter(\.isOpen)
        valueMinor = open.reduce(0) { $0 + $1.marketValueMinor }
        costMinor = open.reduce(0) { $0 + $1.costBasisMinor }
        realizedMinor = Dictionary(grouping: trades, by: \.holdingId).values.reduce(0) { $0 + StockTradeMath.realizedGain(trades: $1) }
        let changes = open.compactMap(\.dayChangeValueMinor)
        dayChangeMinor = changes.isEmpty ? nil : changes.reduce(0, +)
        priceAsOf = open.compactMap(\.priceAsOf).max()
        unquotedCount = open.filter { $0.priceAsOf == nil }.count
    }

    var unrealizedMinor: Int { valueMinor - costMinor }
    var returnFraction: Double? { costMinor > 0 ? Double(unrealizedMinor) / Double(costMinor) : nil }
}

struct StockAllocationSlice: Equatable, Identifiable {
    /// Beyond this, positions fold into "Other" so every color stays distinct.
    static let maxPositions = 5

    let id: String
    let name: String
    let valueMinor: Int
    let share: Double
    /// Nil is "Other". Assigned alphabetically so a stock keeps its color when values reorder it.
    let colorIndex: Int?

    static func slices(for holdings: [StockHolding]) -> [StockAllocationSlice] {
        let open = holdings.filter { $0.isOpen && $0.marketValueMinor > 0 }.sorted { $0.marketValueMinor > $1.marketValueMinor }
        let total = open.reduce(0) { $0 + $1.marketValueMinor }
        guard total > 0 else { return [] }
        let top = open.prefix(maxPositions)
        let alphabetical = top.map(\.symbol).sorted()
        var result = top.map {
            StockAllocationSlice(id: $0.symbol, name: $0.name, valueMinor: $0.marketValueMinor, share: Double($0.marketValueMinor) / Double(total), colorIndex: alphabetical.firstIndex(of: $0.symbol))
        }
        let otherValue = open.dropFirst(maxPositions).reduce(0) { $0 + $1.marketValueMinor }
        if otherValue > 0 {
            result.append(StockAllocationSlice(id: "Other", name: "\(open.count - maxPositions) more", valueMinor: otherValue, share: Double(otherValue) / Double(total), colorIndex: nil))
        }
        return result
    }
}

/// Formats portfolio numbers, masking anything that reveals how much the user holds.
struct StockFormat {
    let hidesAmounts: Bool

    func money(_ amount: Int, _ currency: String) -> String {
        hidesAmounts ? "••••" : (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
    }

    func signedMoney(_ amount: Int, _ currency: String) -> String {
        hidesAmounts ? "••••" : (amount >= 0 ? "+" : "−") + money(abs(amount), currency)
    }

    func shares(_ quantity: Double) -> String {
        hidesAmounts ? "••••" : quantity.formatted()
    }

    func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(1)).sign(strategy: .always())).replacingOccurrences(of: "-", with: "−")
    }
}

private enum PositionSort: String, CaseIterable, Identifiable {
    case value = "Value"
    case gain = "Return"
    case symbol = "Ticker"
    var id: Self { self }
}

struct StockPortfolioView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionController.self) private var session
    @Query(sort: \StockHolding.symbol) private var holdings: [StockHolding]
    @Query(sort: \StockTrade.tradedAt, order: .reverse) private var trades: [StockTrade]
    @AppStorage("ledgerly.hideFinancialAmounts") private var hidesFinancialAmounts = false
    @State private var sync = SyncController()
    @State private var selectedCurrency: String?
    @State private var sort = PositionSort.value
    @State private var importingScreenshot = false
    @State private var refreshingStatus = false
    @State private var chartSymbol: String?

    private var format: StockFormat { StockFormat(hidesAmounts: hidesFinancialAmounts) }
    private var currencies: [String] { Set(holdings.map(\.currency)).sorted() }
    private var currency: String { selectedCurrency.flatMap { currencies.contains($0) ? $0 : nil } ?? currencies.first ?? SupportedCurrency.defaultCode }

    var body: some View {
        let currency = currency
        let scopedHoldings = holdings.filter { $0.currency == currency }
        let scopedTrades = trades.filter { $0.currency == currency }
        let open = scopedHoldings.filter(\.isOpen)
        let closed = scopedHoldings.filter { !$0.isOpen }
        let slices = StockAllocationSlice.slices(for: open)
        List {
            if let error = sync.lastError {
                Section { Text("Couldn’t sync: \(error)").font(.caption).foregroundStyle(.secondary) }
            }
            if holdings.isEmpty {
                ContentUnavailableView(
                    trades.isEmpty ? "No investments synced" : "No positions synced",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text(trades.isEmpty ? "Your investment automation will add holdings and trades here." : "Your imported trades appear below. Run a full history backfill so the automation can calculate positions.")
                )
            } else {
                if currencies.count > 1 {
                    Picker("Currency", selection: Binding(get: { currency }, set: { selectedCurrency = $0 })) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                StockSummarySection(summary: StockPortfolioSummary(holdings: scopedHoldings, trades: scopedTrades), currency: currency, format: format)
                if currency == "TWD", !hidesFinancialAmounts, let chartHolding = open.first(where: { $0.symbol == chartSymbol }) ?? open.max(by: { $0.marketValueMinor < $1.marketValueMinor }) {
                    Section("Price history") {
                        Picker("Stock", selection: Binding(get: { chartHolding.symbol }, set: { chartSymbol = $0 })) {
                            ForEach(open) { Text("\($0.name) · \($0.symbol)").tag($0.symbol) }
                        }
                        StockHistoryChart(symbol: chartHolding.symbol, currency: currency)
                    }
                }
                if slices.count > 1 { StockAllocationSection(slices: slices, currency: currency, format: format) }
                if !open.isEmpty { positionsSection(open, currency: currency) }
                if !closed.isEmpty { closedSection(closed, trades: scopedTrades, currency: currency) }
            }
            if !trades.isEmpty { recentTradesSection }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Investments")
        .sheet(isPresented: $importingScreenshot) { StockScreenshotImportView() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Import holdings screenshot", systemImage: "photo.badge.plus") { importingScreenshot = true }
                    Button(hidesFinancialAmounts ? "Show amounts" : "Hide amounts", systemImage: hidesFinancialAmounts ? "eye" : "eye.slash") { hidesFinancialAmounts.toggle() }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await refreshStatus() } }
                        .disabled(refreshingStatus)
                } label: { Image(systemName: "ellipsis").accessibilityLabel("Investment actions") }
            }
        }
        .task { await StockQuoteService.refresh(context: context) }
        .refreshable { await refreshStatus() }
    }

    private func refreshStatus() async {
        guard !refreshingStatus else { return }
        refreshingStatus = true
        defer { refreshingStatus = false }
        if session.isAuthenticated { await sync.refresh(context: context) }
        await StockQuoteService.refresh(context: context)
    }

    private func positionsSection(_ open: [StockHolding], currency: String) -> some View {
        Section {
            ForEach(sorted(open)) { holding in
                NavigationLink { StockPositionDetailView(holding: holding) } label: { positionRow(holding) }
            }
        } header: {
            HStack {
                Text("Positions")
                Spacer()
                Picker("Sort by", selection: $sort) {
                    ForEach(PositionSort.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption)
            }
            .textCase(nil)
        }
    }

    private func sorted(_ open: [StockHolding]) -> [StockHolding] {
        switch sort {
        case .value: open.sorted { $0.marketValueMinor > $1.marketValueMinor }
        case .gain: open.sorted { ($0.returnFraction ?? 0) > ($1.returnFraction ?? 0) }
        case .symbol: open.sorted { $0.symbol < $1.symbol }
        }
    }

    private func positionRow(_ holding: StockHolding) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(holding.name == holding.symbol ? holding.symbol : "\(holding.symbol) \(holding.name)")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("\(format.shares(holding.quantity)) shares · \(format.money(holding.currentPriceMinor, holding.currency))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text(format.money(holding.marketValueMinor, holding.currency))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Group {
                    if let fraction = holding.returnFraction {
                        Text(format.percent(fraction))
                    } else {
                        Text(format.signedMoney(holding.gainLossMinor, holding.currency))
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(holding.gainLossMinor >= 0 ? .green : .red)
                .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
    }

    private func closedSection(_ closed: [StockHolding], trades: [StockTrade], currency: String) -> some View {
        let tradesByHolding = Dictionary(grouping: trades, by: \.holdingId)
        return Section {
            DisclosureGroup("Closed positions (\(closed.count))") {
                ForEach(closed) { holding in
                    NavigationLink { StockPositionDetailView(holding: holding) } label: {
                        LabeledContent(holding.name == holding.symbol ? holding.symbol : "\(holding.symbol) \(holding.name)") {
                            StockGainText(amount: StockTradeMath.realizedGain(trades: tradesByHolding[holding.id] ?? []), fraction: nil, currency: currency, format: format)
                                .font(.subheadline.weight(.medium))
                        }
                        .lineLimit(1)
                    }
                }
            }
        }
    }

    private var recentTradesSection: some View {
        Section("Recent trades") {
            ForEach(trades.prefix(5)) { StockTradeRow(trade: $0, format: format) }
            if trades.count > 5 {
                NavigationLink("All \(trades.count) trades") { StockTradesView() }
            }
        }
    }
}

private struct StockSummarySection: View {
    let summary: StockPortfolioSummary
    let currency: String
    let format: StockFormat

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Portfolio value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(format.money(summary.valueMinor, currency))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                HStack(spacing: 4) {
                    StockGainText(amount: summary.unrealizedMinor, fraction: summary.returnFraction, currency: currency, format: format)
                        .font(.subheadline.weight(.semibold))
                    Text("unrealized").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            if let dayChange = summary.dayChangeMinor {
                LabeledContent("Last session") {
                    StockGainText(amount: dayChange, fraction: nil, currency: currency, format: format)
                }
            }
            LabeledContent("Cost basis", value: format.money(summary.costMinor, currency))
            LabeledContent("Realized gain") {
                StockGainText(amount: summary.realizedMinor, fraction: nil, currency: currency, format: format)
            }
        } footer: {
            Text(priceNote)
        }
    }

    private var priceNote: String {
        guard let date = summary.priceAsOf else {
            return summary.unquotedCount > 0 ? "Saved prices" : ""
        }
        let asOf = "Daily close · \(date.formatted(date: .abbreviated, time: .omitted))"
        guard summary.unquotedCount > 0 else { return asOf }
        return "\(asOf) · \(summary.unquotedCount) using saved prices"
    }
}

private struct StockAllocationSection: View {
    let slices: [StockAllocationSlice]
    let currency: String
    let format: StockFormat

    var body: some View {
        Section("Allocation") {
            VStack(spacing: 12) {
                bar
                ForEach(slices) { slice in
                    HStack(spacing: 8) {
                        Circle().fill(StockChartColor.slice(slice.colorIndex)).frame(width: 10, height: 10)
                        Text(slice.id).fontWeight(.medium)
                        if slice.name != slice.id {
                            Text(slice.name).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(format.money(slice.valueMinor, currency))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(slice.share.formatted(.percent.precision(.fractionLength(0))))
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let usable = proxy.size.width - gap * CGFloat(slices.count - 1)
            HStack(spacing: gap) {
                ForEach(slices) { slice in
                    Rectangle()
                        .fill(StockChartColor.slice(slice.colorIndex))
                        .frame(width: max(usable * slice.share, 2))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

enum StockChartColor {
    static let buy = dynamic(light: 0x2A78D6, dark: 0x3987E5)
    static let sell = dynamic(light: 0xEB6834, dark: 0xD95926)
    private static let series = [
        buy, sell,
        dynamic(light: 0x1BAF7A, dark: 0x199E70),
        dynamic(light: 0xEDA100, dark: 0xC98500),
        dynamic(light: 0xE87BA4, dark: 0xD55181),
    ]

    static func slice(_ index: Int?) -> Color {
        index.map { series[$0 % series.count] } ?? Color(.systemGray3)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// A signed gain or loss. The sign means it never relies on color alone.
struct StockGainText: View {
    let amount: Int
    let fraction: Double?
    let currency: String
    let format: StockFormat

    var body: some View {
        Text(text)
            .foregroundStyle(amount >= 0 ? .green : .red)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var text: String {
        let money = format.signedMoney(amount, currency)
        guard let fraction else { return money }
        return format.hidesAmounts ? format.percent(fraction) : "\(money) (\(format.percent(fraction)))"
    }
}
