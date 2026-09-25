import SwiftData
import SwiftUI

struct NativeAccountsView: View {
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var showingNewAccount = false
    private var balances: [(currency: String, amount: Int)] {
        let grouped = Dictionary(grouping: accounts.filter(\.isIncludedInNetWorth), by: \.currency)
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
        case "credit", "sharedCredit": "creditcard.trianglebadge.exclamationmark"
        case "investment": "chart.line.uptrend.xyaxis"
        default: AppIcon.cash
        }
    }
}

struct NativeInsightsView: View {
    @Query private var accounts: [CachedAccount]
    @Query private var transactions: [CachedTransaction]
    @Query private var holdings: [StockHolding]
    private var currencies: [String] {
        Array(Set(accounts.map(\.currency) + transactions.map(\.currency) + holdings.map(\.currency))).sorted()
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Summary") {
                    ForEach(currencies.isEmpty ? [SupportedCurrency.defaultCode] : currencies, id: \.self) { currency in
                        let accountWorth = accounts.filter { $0.currency == currency && $0.isIncludedInNetWorth }.reduce(0) { $0 + $1.amountMinor }
                        let investmentWorth = holdings.filter { $0.currency == currency }.reduce(0) { $0 + $1.marketValueMinor }
                        let netWorth = accountWorth + investmentWorth
                        let inflow = transactions.filter { $0.currency == currency && $0.amountMinor > 0 }.reduce(0) { $0 + $1.amountMinor }
                        let outflow = abs(transactions.filter { $0.currency == currency && $0.amountMinor < 0 }.reduce(0) { $0 + $1.amountMinor })
                        VStack(alignment: .leading, spacing: 10) {
                            Text(currency).font(.headline)
                            insightRow("Net worth", netWorth, currency, color: .primary)
                            insightRow("Money in", inflow, currency, color: .green)
                            insightRow("Money out", outflow, currency, color: .red)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Insights")
        }
    }

    private func insightRow(_ label: String, _ amount: Int, _ currency: String, color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(money(amount, currency)).fontWeight(.semibold).foregroundStyle(color)
        }
    }
}

struct NativeActivityView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \RecurringPayment.nextDate) private var recurringPayments: [RecurringPayment]
    @State private var showingNewBill = false
    @State private var showingNewRecurringPayment = false
    @State private var editingRecurringPayment: RecurringPayment?
    @State private var selectedTransaction: TransactionSnapshot?

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
                    ForEach(recurringPayments) { payment in
                        Button { editingRecurringPayment = payment } label: { recurringRow(payment) }
                            .buttonStyle(.plain)
                    }
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
                        let snapshot = TransactionSnapshot(
                            transaction,
                            account: accounts.first { $0.id == transaction.accountId },
                            recurringPayment: recurringPayments.first { $0.id == transaction.recurringPaymentId },
                            transferAccount: accounts.first { $0.id == transaction.transferAccountId }
                        )
                        Button { selectedTransaction = snapshot } label: {
                            HStack(spacing: 10) {
                                transactionRow(transaction)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if transactions.isEmpty {
                        ContentUnavailableView("No activity", systemImage: AppIcon.activity, description: Text("Transactions you add or sync will appear here."))
                    }
                }
            }
            .navigationTitle("Activity")
            .navigationDestination(item: $selectedTransaction) { snapshot in
                TransactionDetailView(transaction: snapshot)
            }
            .sheet(isPresented: $showingNewBill) { NewBillView() }
            .sheet(isPresented: $showingNewRecurringPayment) { NewRecurringPaymentView() }
            .sheet(item: $editingRecurringPayment) { NewRecurringPaymentView(payment: $0) }
        }
    }

    private func recurringRow(_ payment: RecurringPayment) -> some View {
        HStack(spacing: 12) {
            Image(systemName: PaymentIcon.symbol(title: payment.name, category: payment.category, amountMinor: -payment.amountMinor))
                .ledgerlyIcon()
            VStack(alignment: .leading, spacing: 3) {
                Text(payment.name).font(.headline).lineLimit(1)
                Text("\(payment.frequencyLabel) · next due \(payment.nextDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(money(-payment.amountMinor, payment.currency))
                .fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }

    private func transactionRow(_ transaction: CachedTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: PaymentIcon.symbol(title: transaction.title, category: transaction.category, amountMinor: transaction.amountMinor))
                .ledgerlyIcon(color: PaymentIcon.color(amountMinor: transaction.amountMinor))
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.title).font(.headline).lineLimit(1)
                Text(transactionSubtitle(transaction)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(money(transaction.amountMinor, transaction.currency))
                .fontWeight(.semibold)
                .foregroundStyle(PaymentIcon.color(amountMinor: transaction.amountMinor))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .layoutPriority(1)
        }
    }

    private func transactionSubtitle(_ transaction: CachedTransaction) -> String {
        let category = "\(PaymentIcon.directionLabel(amountMinor: transaction.amountMinor)) · \(transaction.category ?? "Uncategorized")"
        guard let id = transaction.recurringPaymentId,
              let payment = recurringPayments.first(where: { $0.id == id }) else { return category }
        return "\(category) · \(payment.name)"
    }

    private func deleteRecurringPayments(at offsets: IndexSet) {
        for index in offsets {
            let payment = recurringPayments[index]
            for transaction in transactions where transaction.recurringPaymentId == payment.id {
                transaction.recurringPaymentId = nil
                context.insert(PendingMutation(
                    entityId: transaction.id, action: "upsert", newDescription: nil, newCategory: nil,
                    newRecurringPaymentId: nil, updatesRecurringPayment: true, baseVersion: transaction.version
                ))
            }
            context.insert(PendingRecurringMutation(entityId: payment.id, action: "delete"))
            context.delete(payment)
        }
        try? context.save()
    }
}

private func money(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
}
