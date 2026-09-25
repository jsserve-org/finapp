import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionController.self) private var session
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query private var transactions: [CachedTransaction]
    @Query(sort: \StockHolding.symbol) private var holdings: [StockHolding]
    @State private var sync = SyncController()
    @State private var selectedMonth = Date()
    @AppStorage("ledgerly.hideFinancialAmounts") private var hidesFinancialAmounts = false

    init() {
        var descriptor = FetchDescriptor<CachedTransaction>(
            sortBy: [SortDescriptor(\CachedTransaction.bookedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1_000
        _transactions = Query(descriptor)
    }

    private var currencies: [String] {
        Array(Set(accounts.map(\.currency) + transactions.map(\.currency) + holdings.map(\.currency))).sorted()
    }

    var body: some View {
        let displayedCurrencies = currencies
        let displayedCategoryTotals = categoryTotals
        let displayedMonths = availableMonths
        let displayedNetWorth = NetWorthCalculator.totals(accounts: accounts, holdings: holdings)
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
                    if displayedCurrencies.isEmpty {
                        ContentUnavailableView("No insights yet", systemImage: AppIcon.insights, description: Text("Add an account or transaction to start seeing your financial summary."))
                    } else {
                        ForEach(displayedCurrencies, id: \.self) { currency in
                            insightSummary(currency: currency, netWorth: displayedNetWorth[currency, default: 0])
                        }
                    }
                }
                Section {
                    if displayedCategoryTotals.isEmpty {
                        ContentUnavailableView(
                            "No spending this month",
                            systemImage: "calendar",
                            description: Text("Choose another month to see its expenses.")
                        )
                    } else {
                        ForEach(Array(displayedCategoryTotals.enumerated()), id: \.offset) { _, item in
                            NavigationLink {
                                CategoryTransactionsView(category: item.category, currency: item.currency, month: selectedMonth)
                            } label: {
                                HStack {
                                    Label(item.category, systemImage: PaymentIcon.symbol(title: "", category: item.category, amountMinor: -1))
                                    Spacer()
                                    Text(hidesFinancialAmounts ? "••••" : money(item.amount, item.currency)).fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Spending by category")
                        Spacer()
                        Menu {
                            ForEach(displayedMonths, id: \.self) { month in
                                Button {
                                    selectedMonth = month
                                } label: {
                                    if Calendar.current.isDate(month, equalTo: selectedMonth, toGranularity: .month) {
                                        Label(month.formatted(.dateTime.month(.wide).year()), systemImage: "checkmark")
                                    } else {
                                        Text(month.formatted(.dateTime.month(.wide).year()))
                                    }
                                }
                            }
                        } label: {
                            Label(selectedMonth.formatted(.dateTime.month(.abbreviated).year()), systemImage: "calendar")
                                .font(.caption.weight(.semibold))
                        }
                        .textCase(nil)
                    }
                }
                investmentSection
            }
            .listStyle(.insetGrouped)
            .refreshable { if session.isAuthenticated { await sync.refresh(context: context) } }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        hidesFinancialAmounts.toggle()
                    } label: {
                        Label(
                            hidesFinancialAmounts ? "Show financial amounts" : "Hide financial amounts",
                            systemImage: hidesFinancialAmounts ? "eye.slash" : "eye"
                        )
                    }
                }
            }
            .task { if session.isAuthenticated { await sync.refresh(context: context) } }
        }
    }

    private func insightSummary(currency: String, netWorth: Int) -> some View {
        let inflow = transactions.filter { $0.currency == currency && $0.amountMinor > 0 }.reduce(0) { $0 + $1.amountMinor }
        let outflow = abs(transactions.filter { $0.currency == currency && $0.amountMinor < 0 }.reduce(0) { $0 + $1.amountMinor })
        return VStack(alignment: .leading, spacing: 10) {
            Text(currency).font(.headline)
            insightRow("Net worth", netWorth, currency, color: .primary)
            insightRow("Money in", inflow, currency, color: .green)
            insightRow("Money out", outflow, currency, color: .red)
        }
        .padding(.vertical, 4)
    }

    private func insightRow(_ label: String, _ amount: Int, _ currency: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(hidesFinancialAmounts ? "••••" : money(amount, currency))
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .accessibilityLabel(hidesFinancialAmounts ? "Hidden" : money(amount, currency))
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
                                Text(hidesFinancialAmounts ? "••••" : money(amount, currency)).fontWeight(.semibold)
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
        let expenses = transactions.filter {
            $0.amountMinor < 0 && $0.bookedDate.map { Calendar.current.isDate($0, equalTo: selectedMonth, toGranularity: .month) } == true
        }
        let grouped = Dictionary(grouping: expenses) { "\($0.currency)|\($0.category ?? "Uncategorized")" }
        return grouped.map { key, values in
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            return (parts.count > 1 ? parts[1] : "Uncategorized", parts[0], abs(values.reduce(0) { $0 + $1.amountMinor }))
        }
        .sorted { $0.amount > $1.amount }
        .prefix(8)
        .map { $0 }
    }

    private var availableMonths: [Date] {
        let calendar = Calendar.current
        var months = transactions.compactMap(\.bookedDate).compactMap {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0))
        }
        if let current = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) {
            months.append(current)
        }
        return Array(Set(months)).sorted(by: >)
    }

    private func money(_ amount: Int, _ currency: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
    }
}

private struct CategoryTransactionsView: View {
    @Query private var transactions: [CachedTransaction]
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \RecurringPayment.nextDate) private var recurringPayments: [RecurringPayment]
    @State private var selectedTransaction: TransactionSnapshot?
    let category: String
    let currency: String
    let month: Date

    init(category: String, currency: String, month: Date) {
        self.category = category
        self.currency = currency
        self.month = month
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? month
        let startISO = ISO8601DateFormatter().string(from: start)
        let endISO = ISO8601DateFormatter().string(from: end)
        _transactions = Query(
            filter: #Predicate<CachedTransaction> {
                $0.bookedAt >= startISO && $0.bookedAt < endISO && $0.currency == currency && $0.amountMinor < 0
            },
            sort: [SortDescriptor(\CachedTransaction.bookedAt, order: .reverse)]
        )
    }

    private var visibleTransactions: [CachedTransaction] {
        transactions.filter { ($0.category ?? "Uncategorized") == category }
    }

    var body: some View {
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let paymentsByID = Dictionary(uniqueKeysWithValues: recurringPayments.map { ($0.id, $0) })
        List {
            Section {
                ForEach(visibleTransactions) { transaction in
                    Button {
                        selectedTransaction = TransactionSnapshot(
                            transaction,
                            account: accountsByID[transaction.accountId],
                            recurringPayment: transaction.recurringPaymentId.flatMap { paymentsByID[$0] },
                            transferAccount: transaction.transferAccountId.flatMap { accountsByID[$0] }
                        )
                    } label: {
                        transactionRow(transaction)
                    }
                    .buttonStyle(.plain)
                }
                if visibleTransactions.isEmpty {
                    ContentUnavailableView("No transactions", systemImage: "calendar", description: Text("No \(category) expenses were recorded in this month."))
                }
            } header: {
                Text("\(visibleTransactions.count) transactions")
            }
        }
        .navigationTitle(category)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(category).font(.headline)
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationDestination(item: $selectedTransaction) { snapshot in
            TransactionDetailView(transaction: snapshot)
        }
    }

    private func transactionRow(_ transaction: CachedTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: PaymentIcon.symbol(title: transaction.title, category: transaction.category, amountMinor: transaction.amountMinor))
                .ledgerlyIcon(color: .red)
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title).font(.headline).lineLimit(1)
                Text(transaction.bookedDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(money(transaction.amountMinor, transaction.currency))
                .fontWeight(.semibold)
                .foregroundStyle(.red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func money(_ amount: Int, _ code: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: code).presentation(.isoCode))
    }
}
