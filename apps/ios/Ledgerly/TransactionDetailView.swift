import SwiftData
import SwiftUI

struct TransactionSnapshot: Identifiable, Hashable {
    let id: String
    let accountID: String
    var title: String
    var amountMinor: Int
    let currency: String
    var bookedDate: Date?
    var pending: Bool
    var category: String?
    var recurringPaymentID: String?
    var updatedDate: Date?
    var accountName: String?
    var institution: String?
    var recurringPaymentName: String?
    var source: String?
    var expensePurpose: String?
    var reimbursementStatus: String?
    var reimbursementTransactionID: String?

    init(_ transaction: CachedTransaction, account: CachedAccount? = nil, recurringPayment: RecurringPayment? = nil) {
        id = transaction.id
        accountID = transaction.accountId
        title = transaction.title
        amountMinor = transaction.amountMinor
        currency = transaction.currency
        bookedDate = transaction.bookedDate
        pending = transaction.pending
        category = transaction.category
        recurringPaymentID = transaction.recurringPaymentId
        updatedDate = transaction.updatedDate
        accountName = account?.name
        institution = account?.institution
        recurringPaymentName = recurringPayment?.name
        source = transaction.source
        expensePurpose = transaction.expensePurpose
        reimbursementStatus = transaction.reimbursementStatus
        reimbursementTransactionID = transaction.reimbursementTransactionId
    }
}

struct TransactionDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var transaction: TransactionSnapshot
    @State private var showingEditor = false
    @State private var showDeleteConfirm = false
    @State private var showReimbursementAccounts = false
    @State private var showMergeReview = false
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var allTransactions: [CachedTransaction]

    private var reimbursementAccounts: [CachedAccount] {
        accounts.filter { $0.currency == transaction.currency && $0.kind != "sharedCredit" }
    }

    private var mergeCandidate: TransactionMergeCandidate? {
        guard let model = fetchTransaction() else { return nil }
        return TransactionMerger.candidate(for: model, among: allTransactions)
    }

    init(transaction: TransactionSnapshot) {
        _transaction = State(initialValue: transaction)
    }

    var body: some View {
        Form {
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
                detailRow("Description", transaction.title)
                detailRow("Category", transaction.category ?? "Uncategorized")
                detailRow("Purpose", purposeLabel(transaction.expensePurpose))
                detailRow("Direction", transaction.amountMinor < 0 ? "Money out" : "Money in")
                HStack(spacing: 12) {
                    Text("Status")
                    Spacer(minLength: 16)
                    Label(transaction.pending ? "Pending" : "Completed", systemImage: transaction.pending ? "clock.fill" : "checkmark.circle.fill")
                        .foregroundStyle(transaction.pending ? .orange : .green)
                }
                .frame(minHeight: 24)
                if let date = transaction.bookedDate {
                    detailRow("Date", date.formatted(date: .long, time: .shortened))
                }
            }

            if transaction.reimbursementStatus != nil {
                Section("Reimbursement") {
                    detailRow("Status", transaction.reimbursementStatus == "reimbursed" ? "Reimbursed" : "Waiting for repayment")
                    if transaction.reimbursementStatus == "pending" {
                        Button("Mark as reimbursed", systemImage: "arrow.uturn.backward.circle.fill") {
                            showReimbursementAccounts = true
                        }
                        .foregroundStyle(.green)
                    }
                }
            }

            Section("Account") {
                detailRow("Account", transaction.accountName ?? "Unknown account")
                if let institution = transaction.institution, !institution.isEmpty {
                    detailRow("Institution", institution)
                }
                detailRow("Currency", transaction.currency)
            }

            Section {
                NavigationLink {
                    RecurringPaymentLinkView(transaction: $transaction)
                } label: {
                    detailRow("Recurring bill", transaction.recurringPaymentName ?? "Not linked")
                }
            } header: {
                Text("Subscription")
            } footer: {
                Text("Ledgerly matches the account, currency, amount, merchant name, and category. Strong matches are linked automatically; uncertain matches stay as suggestions.")
            }

            Section("Record information") {
                detailRow("Source", sourceLabel(transaction.source))
                if let updated = transaction.updatedDate {
                    detailRow("Last updated", updated.formatted(date: .abbreviated, time: .shortened))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transaction ID").font(.caption).foregroundStyle(.secondary)
                    Text(transaction.id).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
            }

            Section {
                if mergeCandidate != nil {
                    Button("Review possible duplicate", systemImage: "arrow.triangle.merge") { showMergeReview = true }
                }
                Button("Edit transaction", systemImage: "pencil") { showingEditor = true }
                Button("Delete transaction", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor, onDismiss: refreshTransaction) {
            EditTransactionView(transaction: transaction)
        }
        .confirmationDialog("Delete this transaction?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("The account balance will be adjusted to remove this transaction.")
        }
        .confirmationDialog("Where was the reimbursement paid?", isPresented: $showReimbursementAccounts, titleVisibility: .visible) {
            ForEach(reimbursementAccounts) { account in
                Button(account.name) { markReimbursed(into: account) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Ledgerly will add a green money-in transaction and link it to this expense.")
        }
        .sheet(isPresented: $showMergeReview) {
            if let candidate = mergeCandidate {
                MergeReviewView(candidate: candidate) {
                    TransactionMerger.merge(candidate, context: context)
                    showMergeReview = false
                    dismiss()
                }
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .foregroundStyle(.primary)
            Spacer(minLength: 16)
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .frame(minHeight: 24)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func delete() {
        guard let transaction = fetchTransaction() else { return }
        if let account = fetchAccount(id: transaction.accountId) {
            account.amountMinor -= transaction.amountMinor
            account.updatedAt = ISO8601DateFormatter().string(from: Date())
            context.insert(PendingAccountMutation(entityId: account.id))
        }
        context.insert(PendingMutation(entityId: transaction.id, action: "delete", newDescription: nil, newCategory: nil, baseVersion: transaction.version))
        context.delete(transaction)
        try? context.save()
        dismiss()
    }

    private func refreshTransaction() {
        guard let model = fetchTransaction() else { return }
        transaction.title = model.title
        transaction.amountMinor = model.amountMinor
        transaction.bookedDate = model.bookedDate
        transaction.pending = model.pending
        transaction.category = model.category
        transaction.recurringPaymentID = model.recurringPaymentId
        transaction.updatedDate = model.updatedDate
        transaction.source = model.source
        transaction.expensePurpose = model.expensePurpose
        transaction.reimbursementStatus = model.reimbursementStatus
        transaction.reimbursementTransactionID = model.reimbursementTransactionId
    }

    private func fetchTransaction() -> CachedTransaction? {
        let id = transaction.id
        var descriptor = FetchDescriptor<CachedTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func fetchAccount(id: String) -> CachedAccount? {
        var descriptor = FetchDescriptor<CachedAccount>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func markReimbursed(into account: CachedAccount) {
        guard let model = fetchTransaction(), model.reimbursementStatus == "pending" else { return }
        _ = ReimbursementService.reimburse(model, into: account, context: context)
        refreshTransaction()
    }

    private func purposeLabel(_ purpose: String?) -> String {
        switch purpose {
        case "school": "School"
        case "someoneElse": "Someone else"
        default: "Personal"
        }
    }

    private func sourceLabel(_ source: String?) -> String {
        switch source {
        case "manual": "Added manually"
        case "automation": "Automation import"
        case "screenshot": "Screenshot import"
        case "reimbursement": "Reimbursement"
        default: "Synced"
        }
    }
}

private struct MergeReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let candidate: TransactionMergeCandidate
    let merge: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Keep imported details") { transactionRow(candidate.imported, label: "Imported") }
                Section("Remove duplicate") { transactionRow(candidate.manual, label: "Manual") }
                Section {
                    Button("Merge transactions", systemImage: "arrow.triangle.merge", action: merge)
                        .fontWeight(.semibold)
                } footer: {
                    Text("The imported record is kept. Missing category, purpose, recurring-bill link, and reimbursement details are copied from the manual record. Your balance is not changed.")
                }
            }
            .navigationTitle("Possible duplicate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func transactionRow(_ item: CachedTransaction, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(item.title).font(.headline).lineLimit(1)
                Spacer()
                Text(money(item.amountMinor, item.currency)).fontWeight(.semibold).lineLimit(1)
            }
            Text("\(label) · \(item.bookedDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown date")")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

private struct EditTransactionView: View {
    let transaction: TransactionSnapshot
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
    @State private var expensePurpose: String
    @State private var reimbursable: Bool

    init(transaction: TransactionSnapshot) {
        self.transaction = transaction
        _title = State(initialValue: transaction.title)
        _category = State(initialValue: transaction.category ?? "")
        _amount = State(initialValue: NSDecimalNumber(value: Double(transaction.amountMinor).magnitude / 100).stringValue)
        _isMoneyOut = State(initialValue: transaction.amountMinor < 0)
        _date = State(initialValue: transaction.bookedDate ?? Date())
        _accountID = State(initialValue: transaction.accountID)
        _pending = State(initialValue: transaction.pending)
        _expensePurpose = State(initialValue: transaction.expensePurpose ?? "personal")
        _reimbursable = State(initialValue: transaction.reimbursementStatus == "pending")
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
                    Picker("Purpose", selection: $expensePurpose) {
                        Text("Personal").tag("personal")
                        Text("School").tag("school")
                        Text("Someone else").tag("someoneElse")
                    }
                    if isMoneyOut, transaction.reimbursementStatus != "reimbursed" {
                        Toggle("I expect reimbursement", isOn: $reimbursable)
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
        guard let model = fetchTransaction(),
              let oldAccount = accounts.first(where: { $0.id == model.accountId }),
              let newAccount = accounts.first(where: { $0.id == accountID }) else { return }
        let newAmount = isMoneyOut ? -parsedAmount : parsedAmount
        if oldAccount.id == newAccount.id {
            oldAccount.amountMinor += newAmount - model.amountMinor
            context.insert(PendingAccountMutation(entityId: oldAccount.id))
        } else {
            oldAccount.amountMinor -= model.amountMinor
            newAccount.amountMinor += newAmount
            context.insert(PendingAccountMutation(entityId: oldAccount.id))
            context.insert(PendingAccountMutation(entityId: newAccount.id))
        }
        let now = ISO8601DateFormatter().string(from: Date())
        oldAccount.updatedAt = now
        newAccount.updatedAt = now
        model.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        model.category = trimmedCategory.isEmpty ? nil : trimmedCategory
        model.amountMinor = newAmount
        model.accountId = newAccount.id
        model.bookedAt = ISO8601DateFormatter().string(from: date)
        model.pending = pending
        model.expensePurpose = expensePurpose
        if model.reimbursementStatus != "reimbursed" {
            model.reimbursementStatus = reimbursable && newAmount < 0 ? "pending" : nil
        }
        model.updatedAt = now
        enqueueFullTransaction(context: context, transactionID: model.id)
        autoLinkRecurringPayment(model, payments: recurringPayments, context: context)
        try? context.save()
        dismiss()
    }

    private func fetchTransaction() -> CachedTransaction? {
        let id = transaction.id
        var descriptor = FetchDescriptor<CachedTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private struct RecurringPaymentLinkView: View {
    @Binding var transaction: TransactionSnapshot
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecurringPayment.name) private var recurringPayments: [RecurringPayment]

    private var compatiblePayments: [RecurringPayment] {
        RecurringPaymentMatcher.compatiblePayments(currency: transaction.currency, accountID: transaction.accountID, payments: recurringPayments)
    }

    var body: some View {
        List {
            Section {
                Button { select(nil) } label: {
                    selectionRow(
                        title: "No recurring bill",
                        subtitle: "Keep this as a one-time transaction",
                        symbol: "minus",
                        selected: transaction.recurringPaymentID == nil
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
                            selected: transaction.recurringPaymentID == payment.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Recurring bills")
            } footer: {
                Text("Showing bills that use \(transaction.currency) and this account.")
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
        guard let model = fetchTransaction() else { return }
        model.recurringPaymentId = paymentID
        model.updatedAt = ISO8601DateFormatter().string(from: Date())
        transaction.recurringPaymentID = paymentID
        transaction.recurringPaymentName = recurringPayments.first(where: { $0.id == paymentID })?.name
        transaction.updatedDate = model.updatedDate
        enqueueFullTransaction(context: context, transactionID: model.id)
        try? context.save()
        dismiss()
    }

    private func fetchTransaction() -> CachedTransaction? {
        let id = transaction.id
        var descriptor = FetchDescriptor<CachedTransaction>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
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
