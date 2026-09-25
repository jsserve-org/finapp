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
                                Image(systemName: AppIcon.account(kind: account.kind)).ledgerlyIcon()
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

}

struct NativeActivityView: View {
    @Environment(\.modelContext) private var context
    @Query private var transactions: [CachedTransaction]
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \RecurringPayment.nextDate) private var recurringPayments: [RecurringPayment]
    @State private var showingNewBill = false
    @State private var showingNewRecurringPayment = false
    @State private var editingRecurringPayment: RecurringPayment?
    @State private var selectedTransaction: TransactionSnapshot?
    @State private var searchText = ""
    @State private var dateFilter = ActivityDateFilter.last90Days
    @State private var showingCustomDates = false
    @State private var customStartDate = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var customEndDate = Date()

    init() {
        var descriptor = FetchDescriptor<CachedTransaction>(
            sortBy: [SortDescriptor(\CachedTransaction.bookedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        _transactions = Query(descriptor)
    }

    private var visibleTransactions: [CachedTransaction] {
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let paymentsByID = Dictionary(uniqueKeysWithValues: recurringPayments.map { ($0.id, $0) })
        return transactions.filter { transaction in
            ActivityDateFilter.includes(
                transaction.bookedDate,
                filter: dateFilter,
                customStart: customStartDate,
                customEnd: customEndDate
            ) && TransactionSearch.matches(
                searchText,
                transaction: transaction,
                account: accountsByID[transaction.accountId],
                recurringPayment: transaction.recurringPaymentId.flatMap { paymentsByID[$0] }
            )
        }
    }

    var body: some View {
        let displayedTransactions = visibleTransactions
        let accountsByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let paymentsByID = Dictionary(uniqueKeysWithValues: recurringPayments.map { ($0.id, $0) })
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

                Section {
                    ForEach(displayedTransactions) { transaction in
                        let snapshot = TransactionSnapshot(
                            transaction,
                            account: accountsByID[transaction.accountId],
                            recurringPayment: transaction.recurringPaymentId.flatMap { paymentsByID[$0] },
                            transferAccount: transaction.transferAccountId.flatMap { accountsByID[$0] }
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
                    } else if displayedTransactions.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No transactions in this range" : "No search results",
                            systemImage: searchText.isEmpty ? "calendar" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "Choose a wider date range to see older activity." : "Try a different search or date range.")
                        )
                    }
                } header: {
                    HStack {
                        Text("Bills & transactions")
                        Spacer()
                        Menu {
                            ForEach(ActivityDateFilter.presets) { filter in
                                Button {
                                    dateFilter = filter
                                } label: {
                                    if dateFilter == filter { Label(filter.label, systemImage: "checkmark") }
                                    else { Text(filter.label) }
                                }
                            }
                            Divider()
                            Button("Custom range…", systemImage: "calendar.badge.clock") {
                                showingCustomDates = true
                            }
                        } label: {
                            Label(dateFilter == .custom ? ActivityDateFilter.customLabel(start: customStartDate, end: customEndDate) : dateFilter.label, systemImage: "calendar")
                                .font(.caption.weight(.semibold))
                        }
                        .textCase(nil)
                    }
                } footer: {
                    Text("Showing \(displayedTransactions.count) transactions. Ledgerly loads at most the newest 500 records to keep Activity responsive.")
                }
            }
            .navigationTitle("Activity")
            .searchable(text: $searchText, prompt: "Search transactions")
            .navigationDestination(item: $selectedTransaction) { snapshot in
                TransactionDetailView(transaction: snapshot)
            }
            .sheet(isPresented: $showingNewBill) { NewBillView() }
            .sheet(isPresented: $showingNewRecurringPayment) { NewRecurringPaymentView() }
            .sheet(item: $editingRecurringPayment) { NewRecurringPaymentView(payment: $0) }
            .sheet(isPresented: $showingCustomDates) {
                ActivityCustomDateView(startDate: $customStartDate, endDate: $customEndDate) {
                    dateFilter = .custom
                }
            }
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
            VStack(alignment: .trailing, spacing: 2) {
                Text(money(transaction.amountMinor, transaction.currency))
                    .fontWeight(.semibold)
                    .foregroundStyle(PaymentIcon.color(amountMinor: transaction.amountMinor))
                if let originalAmountMinor = transaction.originalAmountMinor,
                   let originalCurrency = transaction.originalCurrency {
                    Text("Originally \(money(originalAmountMinor, originalCurrency))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
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
            let paymentID = payment.id
            let linkedDescriptor = FetchDescriptor<CachedTransaction>(predicate: #Predicate { $0.recurringPaymentId == paymentID })
            let linkedTransactions = (try? context.fetch(linkedDescriptor)) ?? []
            for transaction in linkedTransactions {
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

enum ActivityDateFilter: String, CaseIterable, Identifiable {
    case last7Days, last30Days, last90Days, thisYear, all, custom

    static let presets: [ActivityDateFilter] = [.last7Days, .last30Days, .last90Days, .thisYear, .all]
    var id: String { rawValue }
    var label: String {
        switch self {
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .last90Days: "Last 90 days"
        case .thisYear: "This year"
        case .all: "All loaded"
        case .custom: "Custom"
        }
    }

    static func includes(_ date: Date?, filter: ActivityDateFilter, customStart: Date, customEnd: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let date else { return false }
        let start: Date?
        let end: Date
        switch filter {
        case .last7Days: start = calendar.date(byAdding: .day, value: -7, to: now); end = now
        case .last30Days: start = calendar.date(byAdding: .day, value: -30, to: now); end = now
        case .last90Days: start = calendar.date(byAdding: .day, value: -90, to: now); end = now
        case .thisYear: start = calendar.date(from: calendar.dateComponents([.year], from: now)); end = now
        case .all: return true
        case .custom:
            start = calendar.startOfDay(for: min(customStart, customEnd))
            end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(customStart, customEnd))) ?? max(customStart, customEnd)
        }
        guard let start else { return true }
        return date >= start && date <= end
    }

    static func customLabel(start: Date, end: Date) -> String {
        "\(min(start, end).formatted(.dateTime.month(.abbreviated).day()))–\(max(start, end).formatted(.dateTime.month(.abbreviated).day()))"
    }
}

private struct ActivityCustomDateView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var startDate: Date
    @Binding var endDate: Date
    let apply: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Date range") {
                    DatePicker("From", selection: $startDate, displayedComponents: .date)
                    DatePicker("Through", selection: $endDate, displayedComponents: .date)
                }
                Section {
                    Text("Only transactions booked between these dates will appear.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Custom dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { apply(); dismiss() }
                }
            }
        }
    }
}

enum TransactionSearch {
    static func matches(_ query: String, transaction: CachedTransaction, account: CachedAccount?, recurringPayment: RecurringPayment?) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let date = transaction.bookedDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        let fields = [
            transaction.title, transaction.category ?? "", transaction.currency,
            account?.name ?? "", account?.institution ?? "", recurringPayment?.name ?? "",
            money(transaction.amountMinor, transaction.currency), date,
        ]
        return fields.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

private func money(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
}
