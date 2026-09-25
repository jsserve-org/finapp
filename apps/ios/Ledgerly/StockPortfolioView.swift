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
    @State private var showingNewTrade = false

    private var totals: [(String, Int)] {
        Dictionary(grouping: holdings, by: \.currency)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.marketValueMinor }) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        List {
            if holdings.isEmpty {
                ContentUnavailableView {
                    Label("No investments", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("Add a buy or sell trade. Ledgerly can link its cash movement to one of your accounts.")
                } actions: {
                    Button("Add trade", systemImage: "plus") { showingNewTrade = true }
                        .buttonStyle(.borderedProminent)
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
                Section("Recent trades") {
                    ForEach(trades.prefix(20)) { trade in tradeRow(trade) }
                }
            }
        }
        .navigationTitle("Investments")
        .toolbar { Button("Add trade", systemImage: "plus") { showingNewTrade = true } }
        .sheet(isPresented: $showingNewTrade) { NewStockTradeView() }
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

private struct NewStockTradeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query private var holdings: [StockHolding]
    @State private var symbol = ""
    @State private var companyName = ""
    @State private var side = "buy"
    @State private var quantity = ""
    @State private var price = ""
    @State private var fees = "0"
    @State private var currency = SupportedCurrency.defaultCode
    @State private var tradedAt = Date()
    @State private var accountID = ""
    @State private var validationMessage: String?

    private var compatibleAccounts: [CachedAccount] { accounts.filter { $0.currency == currency && $0.kind != "sharedCredit" } }
    private var parsedQuantity: Double { Double(quantity.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var parsedPrice: Int { minorUnits(price) }
    private var parsedFees: Int { minorUnits(fees) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trade") {
                    Picker("Side", selection: $side) {
                        Text("Buy").tag("buy"); Text("Sell").tag("sell")
                    }.pickerStyle(.segmented)
                    TextField("Ticker, e.g. AAPL", text: $symbol).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Company name", text: $companyName)
                    TextField("Shares", text: $quantity).keyboardType(.decimalPad)
                    TextField("Price per share", text: $price).keyboardType(.decimalPad)
                    TextField("Fees", text: $fees).keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(SupportedCurrency.all) { Text($0.code).tag($0.code) }
                    }
                    DatePicker("Trade date", selection: $tradedAt)
                }
                Section {
                    Picker("Cash account", selection: $accountID) {
                        Text("Do not change an account").tag("")
                        ForEach(compatibleAccounts) { Text($0.name).tag($0.id) }
                    }
                } header: { Text("Bank link") } footer: {
                    Text("A buy subtracts cash; a sell returns cash. Ledgerly also adds the matching account transaction.")
                }
                if let validationMessage { Section { Text(validationMessage).foregroundStyle(.red) } }
            }
            .navigationTitle("Add stock trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onChange(of: currency) { _, _ in if !compatibleAccounts.contains(where: { $0.id == accountID }) { accountID = "" } }
        }
    }

    private var canSave: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty && parsedQuantity > 0 && parsedPrice > 0
    }

    private func minorUnits(_ value: String) -> Int {
        let decimal = Decimal(string: value.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save() {
        let ticker = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let existing = holdings.first { $0.symbol.uppercased() == ticker && $0.currency == currency }
        if side == "sell", (existing?.quantity ?? 0) < parsedQuantity {
            validationMessage = "You only have \((existing?.quantity ?? 0).formatted()) shares available."
            return
        }
        let now = ISO8601DateFormatter().string(from: tradedAt)
        let holding = existing ?? StockHolding(symbol: ticker, name: companyName.isEmpty ? ticker : companyName, quantity: 0, averageCostMinor: parsedPrice, currentPriceMinor: parsedPrice, currency: currency, linkedAccountId: accountID.isEmpty ? nil : accountID)
        if existing == nil { context.insert(holding) }
        if side == "buy" {
            let newQuantity = holding.quantity + parsedQuantity
            holding.averageCostMinor = StockTradeMath.averageCost(oldQuantity: holding.quantity, oldAverageMinor: holding.averageCostMinor, boughtQuantity: parsedQuantity, priceMinor: parsedPrice, feesMinor: parsedFees)
            holding.quantity = newQuantity
        } else {
            holding.quantity -= parsedQuantity
        }
        holding.name = companyName.trimmingCharacters(in: .whitespaces).isEmpty ? holding.name : companyName.trimmingCharacters(in: .whitespaces)
        holding.currentPriceMinor = parsedPrice
        holding.linkedAccountId = accountID.isEmpty ? holding.linkedAccountId : accountID
        holding.updatedAt = ISO8601DateFormatter().string(from: Date())
        context.insert(PendingStockMutation(entityId: holding.id, entity: "stockHolding"))

        let trade = StockTrade(holdingId: holding.id, symbol: ticker, side: side, quantity: parsedQuantity, priceMinor: parsedPrice, feesMinor: parsedFees, currency: currency, tradedAt: now, linkedAccountId: accountID.isEmpty ? nil : accountID)
        context.insert(trade)
        context.insert(PendingStockMutation(entityId: trade.id, entity: "stockTrade"))
        if let account = accounts.first(where: { $0.id == accountID }) {
            let cashChange = StockTradeMath.cashChange(side: side, quantity: parsedQuantity, priceMinor: parsedPrice, feesMinor: parsedFees)
            account.amountMinor += cashChange
            account.updatedAt = ISO8601DateFormatter().string(from: Date())
            context.insert(PendingAccountMutation(entityId: account.id))
            let transaction = CachedTransaction(dto: TransactionDTO(
                id: UUID().uuidString.lowercased(), accountId: account.id,
                description: "\(side == "buy" ? "Buy" : "Sell") \(ticker)",
                amount: Money(amountMinor: cashChange, currency: currency), bookedAt: now,
                pending: false, category: "Investments", source: "stockTrade", updatedAt: now
            ), initialVersion: 0)
            context.insert(transaction)
            context.insert(PendingTransactionCreate(entityId: transaction.id))
        }
        try? context.save()
        dismiss()
    }
}

private func stockMoney(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
}

private func signedStockMoney(_ amount: Int, _ currency: String) -> String {
    let value = stockMoney(abs(amount), currency)
    return amount >= 0 ? "+\(value)" : "−\(value)"
}
