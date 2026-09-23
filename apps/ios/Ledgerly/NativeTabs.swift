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
                                Image(systemName: accountSymbol(account)).ledgerlyIcon()
                            }
                            .badge(Text(money(account.amountMinor, account.currency)))
                        }
                    }
                    if accounts.isEmpty {
                        ContentUnavailableView("No accounts", systemImage: AppIcon.account, description: Text("Create an account on this device. Sync is optional."))
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
        default: AppIcon.cash
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
    @State private var showingNewBill = false
    @State private var showingNewRecurringPayment = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Button { showingNewBill = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .symbolRenderingMode(.monochrome)
                                    .fontWeight(.bold)
                                Text("Add one-time bill")
                                    .fontWeight(.semibold)
                            }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0, green: 0.32, blue: 0.68))
                        .controlSize(.large)
                        .accessibilityLabel("Add one-time bill")

                        Button { showingNewRecurringPayment = true } label: {
                            HStack(spacing: 10) {
                                Image(systemName: AppIcon.recurring)
                                    .symbolRenderingMode(.monochrome)
                                    .fontWeight(.bold)
                                Text("Add recurring bill")
                                    .fontWeight(.semibold)
                            }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.bordered)
                        .tint(.primary)
                        .controlSize(.large)
                        .accessibilityLabel("Add recurring bill")
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("One-time bills use a payment date. Recurring bills repeat on a schedule.")
                }

                Section {
                    ForEach(recurringPayments) { payment in recurringRow(payment) }
                        .onDelete(perform: deleteRecurringPayments)
                    if recurringPayments.isEmpty {
                        Text("No recurring bills yet.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Recurring bills")
                } footer: {
                    Text("These repeat on the frequency and next due date you choose.")
                }

                Section("Bills & transactions") {
                    ForEach(transactions) { transaction in
                        NavigationLink { TransactionDetailView(transactionID: transaction.id) } label: { transactionRow(transaction) }
                    }
                    if transactions.isEmpty {
                        ContentUnavailableView("No activity", systemImage: AppIcon.activity, description: Text("Transactions you add or sync will appear here."))
                    }
                }
            }
            .navigationTitle("Activity")
            .sheet(isPresented: $showingNewBill) { NewBillView() }
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
                    Text("\(payment.frequencyLabel) · next due \(payment.nextDate.formatted(date: .abbreviated, time: .omitted))").font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: AppIcon.recurring).ledgerlyIcon() }
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
        for index in offsets {
            let payment = recurringPayments[index]
            context.insert(PendingRecurringMutation(entityId: payment.id, action: "delete"))
            context.delete(payment)
        }
        try? context.save()
    }
}

private func money(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
}
