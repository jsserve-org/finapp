import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionController.self) private var session
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query private var transactions: [CachedTransaction]
    @Query(sort: \StockHolding.symbol) private var holdings: [StockHolding]
    @State private var sync = SyncController()

    private var currencies: [String] {
        Array(Set(accounts.map(\.currency) + transactions.map(\.currency) + holdings.map(\.currency))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = sync.lastError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } footer: {
                        Text("Open Settings → Server after updating either the app or backend.")
                    }
                }
                Section("Summary") {
                    if currencies.isEmpty {
                        ContentUnavailableView("No insights yet", systemImage: AppIcon.insights, description: Text("Add an account or transaction to start seeing your financial summary."))
                    } else {
                        ForEach(currencies, id: \.self) { currency in
                            insightSummary(currency: currency)
                        }
                    }
                }
                if !categoryTotals.isEmpty {
                    Section("Spending by category") {
                        ForEach(Array(categoryTotals.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Label(item.category, systemImage: PaymentIcon.symbol(title: "", category: item.category, amountMinor: -1))
                                Spacer()
                                Text(money(item.amount, item.currency)).fontWeight(.semibold)
                            }
                        }
                    }
                }
                investmentSection
            }
            .listStyle(.insetGrouped)
            .refreshable { if session.isAuthenticated { await sync.refresh(context: context) } }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .task { if session.isAuthenticated { await sync.refresh(context: context) } }
        }
    }

    private func insightSummary(currency: String) -> some View {
        let accountWorth = accounts.filter { $0.currency == currency && $0.isIncludedInNetWorth }.reduce(0) { $0 + $1.amountMinor }
        let investmentWorth = holdings.filter { $0.currency == currency }.reduce(0) { $0 + $1.marketValueMinor }
        let inflow = transactions.filter { $0.currency == currency && $0.amountMinor > 0 }.reduce(0) { $0 + $1.amountMinor }
        let outflow = abs(transactions.filter { $0.currency == currency && $0.amountMinor < 0 }.reduce(0) { $0 + $1.amountMinor })
        return VStack(alignment: .leading, spacing: 10) {
            Text(currency).font(.headline)
            insightRow("Net worth", accountWorth + investmentWorth, currency, color: .primary)
            insightRow("Money in", inflow, currency, color: .green)
            insightRow("Money out", outflow, currency, color: .red)
        }
        .padding(.vertical, 4)
    }

    private func insightRow(_ label: String, _ amount: Int, _ currency: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(money(amount, currency)).fontWeight(.semibold).foregroundStyle(color)
        }
    }

    private var investmentSection: some View {
        Section("Investments") {
            NavigationLink { StockPortfolioView() } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    if holdings.isEmpty {
                        Text("Add your first stock trade")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(portfolioTotals, id: \.0) { currency, amount in
                            HStack {
                                Text(currency).foregroundStyle(.secondary)
                                Spacer()
                                Text(money(amount, currency)).fontWeight(.semibold)
                            }
                        }
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var portfolioTotals: [(String, Int)] {
        Dictionary(grouping: holdings, by: \.currency)
            .map { ($0.key, $0.value.reduce(0) { $0 + $1.marketValueMinor }) }
            .sorted { $0.0 < $1.0 }
    }

    private var categoryTotals: [(category: String, currency: String, amount: Int)] {
        let expenses = transactions.filter { $0.amountMinor < 0 }
        let grouped = Dictionary(grouping: expenses) { "\($0.currency)|\($0.category ?? "Uncategorized")" }
        return grouped.map { key, values in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return (parts.count > 1 ? parts[1] : "Uncategorized", parts[0], abs(values.reduce(0) { $0 + $1.amountMinor }))
        }
        .sorted { $0.amount > $1.amount }
        .prefix(8)
        .map { $0 }
    }

    private func money(_ amount: Int, _ currency: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
    }
}
