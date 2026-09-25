import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    let transactionID: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [CachedTransaction]
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \RecurringPayment.name) private var recurringPayments: [RecurringPayment]
    @State private var showingEditor = false
    @State private var showDeleteConfirm = false

    private var transaction: CachedTransaction? { transactions.first { $0.id == transactionID } }
    private var account: CachedAccount? { transaction.flatMap { selected in accounts.first { $0.id == selected.accountId } } }
    private var recurringPayment: RecurringPayment? { transaction.flatMap { selected in recurringPayments.first { $0.id == selected.recurringPaymentId } } }
    private var suggestedPayment: RecurringPayment? {
        guard let transaction, transaction.recurringPaymentId == nil else { return nil }
        return RecurringPaymentMatcher.bestMatch(for: transaction, payments: recurringPayments)?.payment
    }

    var body: some View {
        Form {
            if let transaction {
                Section {
                VStack(spacing: 10) {
                    Image(systemName: PaymentIcon.symbol(title: transaction.title, category: transaction.category, amountMinor: transaction.amountMinor))
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(PaymentIcon.color(amountMinor: transaction.amountMinor))
                    Text(PaymentIcon.directionLabel(amountMinor: transaction.amountMinor))
                        .font(.headline)
                        .foregroundStyle(PaymentIcon.color(amountMinor: transaction.amountMinor))
                    Text(absoluteMoney(transaction.amountMinor, transaction.currency))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(PaymentIcon.color(amountMinor: transaction.amountMinor))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Payment details") {
                LabeledContent("Description", value: transaction.title)
                LabeledContent("Category", value: transaction.category ?? "Uncategorized")
                LabeledContent("Direction", value: transaction.amountMinor < 0 ? "Money out" : "Money in")
                LabeledContent("Status") {
                    Label(transaction.pending ? "Pending" : "Completed", systemImage: transaction.pending ? "clock.fill" : "checkmark.circle.fill")
                        .foregroundStyle(transaction.pending ? .orange : .green)
                }
                if let date = transaction.bookedDate {
                    LabeledContent("Date", value: date.formatted(date: .long, time: .shortened))
                }
            }

            Section("Account") {
                LabeledContent("Account", value: account?.name ?? "Unknown account")
                if let institution = account?.institution, !institution.isEmpty {
                    LabeledContent("Institution", value: institution)
                }
                LabeledContent("Currency", value: transaction.currency)
            }

            Section {
                NavigationLink {
                    RecurringPaymentLinkView(transactionID: transaction.id)
                } label: {
                    LabeledContent("Recurring bill", value: recurringPayment?.name ?? "Not linked")
                }
                if let suggestedPayment {
                    Button {
                        link(to: suggestedPayment.id)
                    } label: {
                        Label("Link suggested: \(suggestedPayment.name)", systemImage: "wand.and.stars")
                    }
                }
            } header: {
                Text("Subscription")
            } footer: {
                Text("Ledgerly matches the account, currency, amount, merchant name, and category. Strong matches are linked automatically; uncertain matches stay as suggestions.")
            }

            Section("Record information") {
                LabeledContent("Source", value: transaction.category == "Screenshot Sync" ? "Screenshot import" : "Manual or synced")
                if let updated = transaction.updatedDate {
                    LabeledContent("Last updated", value: updated.formatted(date: .abbreviated, time: .shortened))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transaction ID").font(.caption).foregroundStyle(.secondary)
                    Text(transaction.id).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }

            Section {
                Button("Edit transaction", systemImage: "pencil") { showingEditor = true }
                Button("Delete transaction", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
            }
            } else {
                ContentUnavailableView(
                    "Transaction unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This transaction may have been removed during sync.")
                )
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            if let transaction { EditTransactionView(transaction: transaction) }
        }
        .confirmationDialog("Delete this transaction?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("The account balance will be adjusted to remove this transaction.")
        }
    }

    private func link(to paymentID: String?) {
        guard let transaction else { return }
        transaction.recurringPaymentId = paymentID
        transaction.updatedAt = ISO8601DateFormatter().string(from: Date())
        enqueueFullTransaction(context: context, transactionID: transaction.id)
        try? context.save()
    }

    private func delete() {
        guard let transaction else { return }
        if let account {
            account.amountMinor -= transaction.amountMinor
            account.updatedAt = ISO8601DateFormatter().string(from: Date())
            context.insert(PendingAccountMutation(entityId: account.id))
        }
        context.insert(PendingMutation(entityId: transaction.id, action: "delete", newDescription: nil, newCategory: nil, baseVersion: transaction.version))
        context.delete(transaction)
        try? context.save()
        dismiss()
    }
}

private struct EditTransactionView: View {
    let transaction: CachedTransaction
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \RecurringPayment.name) private var recurringPayments: [RecurringPayment]
    @State private var title: String
    @State private var category: String
    @State private var amount: String
    @State private var isMoneyOut: Bool
    @State private var date: Date
    @State private var accountID: String
    @State private var pending: Bool

    init(transaction: CachedTransaction) {
        self.transaction = transaction
        _title = State(initialValue: transaction.title)
        _category = State(initialValue: transaction.category ?? "")
        _amount = State(initialValue: NSDecimalNumber(value: Double(transaction.amountMinor).magnitude / 100).stringValue)
        _isMoneyOut = State(initialValue: transaction.amountMinor < 0)
        _date = State(initialValue: transaction.bookedDate ?? Date())
        _accountID = State(initialValue: transaction.accountId)
        _pending = State(initialValue: transaction.pending)
    }

    private var compatibleAccounts: [CachedAccount] { accounts.filter { $0.currency == transaction.currency } }
    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    Picker("Direction", selection: $isMoneyOut) {
                        Text("Money out").tag(true)
                        Text("Money in").tag(false)
                    }
                    .pickerStyle(.segmented)
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    LabeledContent("Currency", value: transaction.currency)
                    Toggle("Pending", isOn: $pending)
                }
                Section("Details") {
                    TextField("Description", text: $title)
                    TextField("Category", text: $category)
                    DatePicker("Date and time", selection: $date)
                    Picker("Account", selection: $accountID) {
                        ForEach(compatibleAccounts) { account in Text(account.name).tag(account.id) }
                    }
                }
            }
            .navigationTitle("Edit transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedAmount <= 0 || accountID.isEmpty)
                }
            }
        }
    }

    private func save() {
        guard let oldAccount = accounts.first(where: { $0.id == transaction.accountId }),
              let newAccount = accounts.first(where: { $0.id == accountID }) else { return }
        let newAmount = isMoneyOut ? -parsedAmount : parsedAmount
        if oldAccount.id == newAccount.id {
            oldAccount.amountMinor += newAmount - transaction.amountMinor
            context.insert(PendingAccountMutation(entityId: oldAccount.id))
        } else {
            oldAccount.amountMinor -= transaction.amountMinor
            newAccount.amountMinor += newAmount
            context.insert(PendingAccountMutation(entityId: oldAccount.id))
            context.insert(PendingAccountMutation(entityId: newAccount.id))
        }
        let now = ISO8601DateFormatter().string(from: Date())
        oldAccount.updatedAt = now
        newAccount.updatedAt = now
        transaction.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.category = trimmedCategory.isEmpty ? nil : trimmedCategory
        transaction.amountMinor = newAmount
        transaction.accountId = newAccount.id
        transaction.bookedAt = ISO8601DateFormatter().string(from: date)
        transaction.pending = pending
        transaction.updatedAt = now
        enqueueFullTransaction(context: context, transactionID: transaction.id)
        autoLinkRecurringPayment(transaction, payments: recurringPayments, context: context)
        try? context.save()
        dismiss()
    }
}

private struct RecurringPaymentLinkView: View {
    let transactionID: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [CachedTransaction]
    @Query(sort: \RecurringPayment.name) private var recurringPayments: [RecurringPayment]

    private var transaction: CachedTransaction? { transactions.first { $0.id == transactionID } }
    private var compatiblePayments: [RecurringPayment] {
        guard let transaction else { return [] }
        return RecurringPaymentMatcher.compatiblePayments(for: transaction, payments: recurringPayments)
    }

    var body: some View {
        List {
            Section {
                Button { select(nil) } label: {
                    selectionRow(
                        title: "No recurring bill",
                        subtitle: "Keep this as a one-time transaction",
                        symbol: "minus",
                        selected: transaction?.recurringPaymentId == nil
                    )
                }
                .buttonStyle(.plain)
            }

            Section {
                ForEach(compatiblePayments) { payment in
                    Button { select(payment.id) } label: {
                        selectionRow(
                            title: payment.name,
                            subtitle: "\(payment.frequencyLabel) · \(money(payment.amountMinor, payment.currency))",
                            symbol: PaymentIcon.symbol(title: payment.name, category: payment.category, amountMinor: -1),
                            selected: transaction?.recurringPaymentId == payment.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Recurring bills")
            } footer: {
                Text(transaction.map { "Showing bills that use \($0.currency) and this account." } ?? "This transaction is no longer available.")
            }
        }
        .listSectionSpacing(.compact)
        .navigationTitle("Link recurring bill")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func selectionRow(title: String, subtitle: String, symbol: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
    }

    private func select(_ paymentID: String?) {
        guard let transaction else { return }
        transaction.recurringPaymentId = paymentID
        transaction.updatedAt = ISO8601DateFormatter().string(from: Date())
        enqueueFullTransaction(context: context, transactionID: transaction.id)
        try? context.save()
        dismiss()
    }
}

@MainActor
func enqueueFullTransaction(context: ModelContext, transactionID: String) {
    let pending = (try? context.fetch(FetchDescriptor<PendingTransactionCreate>())) ?? []
    if !pending.contains(where: { $0.entityId == transactionID }) {
        context.insert(PendingTransactionCreate(entityId: transactionID))
    }
}

private func money(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
}

private func absoluteMoney(_ amount: Int, _ currency: String) -> String {
    (Double(amount).magnitude / 100).formatted(.currency(code: currency).presentation(.isoCode))
}
