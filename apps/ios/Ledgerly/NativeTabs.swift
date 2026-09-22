import SwiftData
import SwiftUI

struct NativeAccountsView: View {
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var showingNewAccount = false
    private var balances: [(currency: String, amount: Int)] {
        let grouped = Dictionary(grouping: accounts, by: \.currency)
        return grouped.map { (currency: $0.key, amount: $0.value.reduce(0) { $0 + $1.amountMinor }) }
            .sorted { $0.currency < $1.currency }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Total") {
                    if balances.isEmpty {
                        LabeledContent("Balance") {
                            Text(money(0, SupportedCurrency.defaultCode)).font(.title2.bold())
                        }
                    } else {
                        ForEach(balances, id: \.currency) { balance in
                            LabeledContent(balance.currency) {
                                Text(money(balance.amount, balance.currency)).font(.title2.bold())
                            }
                        }
                    }
                    LabeledContent("Accounts", value: accounts.count.formatted())
                }
                Section("Accounts") {
                    ForEach(accounts) { account in
                        NavigationLink { AccountDetailView(accountID: account.id) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(account.name).font(.headline)
                                    Text("\(account.institution) · \(account.displayKind)").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: accountSymbol(account)).foregroundStyle(.blue)
                            }
                            .badge(Text(money(account.amountMinor, account.currency)))
                        }
                    }
                    if accounts.isEmpty {
                        ContentUnavailableView("No accounts", systemImage: "building.columns", description: Text("Create an account on this device. Sync is optional."))
                    }
                }
            }
            .navigationTitle("Accounts")
            .toolbar { Button("Add account", systemImage: "plus") { showingNewAccount = true } }
            .sheet(isPresented: $showingNewAccount) { NewAccountView() }
        }
    }

    private func accountSymbol(_ account: CachedAccount) -> String {
        switch account.kind {
        case "checking": "creditcard.fill"
        case "savings": "banknote.fill"
        case "credit": "creditcard.trianglebadge.exclamationmark"
        case "investment": "chart.line.uptrend.xyaxis"
        default: "wallet.bifold.fill"
        }
    }
}

struct NativeInsightsView: View {
    @Query private var accounts: [CachedAccount]
    @Query private var transactions: [CachedTransaction]
    private var currencies: [String] {
        Array(Set(accounts.map(\.currency) + transactions.map(\.currency))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    ForEach(currencies.isEmpty ? [SupportedCurrency.defaultCode] : currencies, id: \.self) { currency in
                        let netWorth = accounts.filter { $0.currency == currency }.reduce(0) { $0 + $1.amountMinor }
                        let inflow = transactions.filter { $0.currency == currency && $0.amountMinor > 0 }.reduce(0) { $0 + $1.amountMinor }
                        let outflow = abs(transactions.filter { $0.currency == currency && $0.amountMinor < 0 }.reduce(0) { $0 + $1.amountMinor })
                        LabeledContent("\(currency) net worth", value: money(netWorth, currency))
                        LabeledContent("\(currency) money in", value: money(inflow, currency))
                        LabeledContent("\(currency) money out", value: money(outflow, currency))
                    }
                }
                Section("Snapshot") {
                    Label(transactions.isEmpty ? "Add transactions to see spending patterns." : "Based on \(transactions.count) saved transaction\(transactions.count == 1 ? "" : "s").", systemImage: "chart.pie")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Insights")
        }
    }
}

struct NativeActivityView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]
    @Query(sort: \RecurringPayment.nextDate) private var recurringPayments: [RecurringPayment]
    @State private var showingNewRecurringPayment = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(recurringPayments) { payment in recurringRow(payment) }
                        .onDelete(perform: deleteRecurringPayments)
                    if recurringPayments.isEmpty {
                        Button { showingNewRecurringPayment = true } label: {
                            Label("Add rent, subscriptions, or regular bills", systemImage: "calendar.badge.plus")
                        }
                    }
                } header: {
                    Text("Recurring payments")
                } footer: {
                    Text("Ledgerly tracks schedules only. It never moves money or charges an account.")
                }

                Section("Transactions") {
                    ForEach(transactions) { transaction in
                        NavigationLink { TransactionDetailView(transactionID: transaction.id) } label: { transactionRow(transaction) }
                    }
                    if transactions.isEmpty {
                        ContentUnavailableView("No activity", systemImage: "list.bullet.rectangle", description: Text("Transactions you add or sync will appear here."))
                    }
                }
            }
            .navigationTitle("Activity")
            .toolbar { Button("Add recurring payment", systemImage: "plus") { showingNewRecurringPayment = true } }
            .sheet(isPresented: $showingNewRecurringPayment) { NewRecurringPaymentView() }
        }
    }

    private func recurringRow(_ payment: RecurringPayment) -> some View {
        LabeledContent {
            Text(money(-payment.amountMinor, payment.currency)).fontWeight(.semibold)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(payment.name).font(.headline)
                    Text("\(payment.frequencyLabel) · \(payment.nextDate.formatted(date: .abbreviated, time: .omitted))").font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: "repeat").foregroundStyle(.blue) }
        }
    }

    private func transactionRow(_ transaction: CachedTransaction) -> some View {
        LabeledContent {
            Text(money(transaction.amountMinor, transaction.currency)).foregroundStyle(transaction.amountMinor > 0 ? .blue : .primary)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title).font(.headline)
                Text(transaction.category ?? "Uncategorized").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func deleteRecurringPayments(at offsets: IndexSet) {
        for index in offsets { context.delete(recurringPayments[index]) }
        try? context.save()
    }
}

private func money(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
}
