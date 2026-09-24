import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    let transactionID: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [CachedTransaction]
    @Query(sort: \RecurringPayment.name) private var recurringPayments: [RecurringPayment]
    @State private var editedTitle = ""
    @State private var editedCategory = ""
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var selectedRecurringPaymentID = ""

    init(transactionID: String) {
        self.transactionID = transactionID
        let id = transactionID
        _transactions = Query(filter: #Predicate<CachedTransaction> { $0.id == id })
    }

    var body: some View {
        Form {
            if let transaction = transactions.first {
                Section("Transaction") {
                    HStack {
                        Spacer()
                        Image(systemName: PaymentIcon.symbol(title: transaction.title, category: transaction.category, amountMinor: transaction.amountMinor))
                            .font(.largeTitle)
                            .foregroundStyle(PaymentIcon.color(amountMinor: transaction.amountMinor))
                        Spacer()
                    }
                    if isEditing {
                        TextField("Description", text: $editedTitle)
                        TextField("Category", text: $editedCategory)
                    } else {
                        LabeledContent("Description", value: transaction.title)
                        LabeledContent("Category", value: transaction.category ?? "Uncategorized")
                    }
                    LabeledContent("Amount") {
                        Text(money(transaction.amountMinor, transaction.currency)).font(.title3.bold())
                    }
                    if let date = transaction.bookedDate {
                        LabeledContent("Date", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
                    if transaction.pending { Label("Pending", systemImage: "clock").foregroundStyle(.orange) }
                }
                Section {
                    Picker("Recurring bill", selection: $selectedRecurringPaymentID) {
                        Text("Not linked").tag("")
                        ForEach(compatiblePayments(for: transaction)) { payment in
                            Text(payment.name).tag(payment.id)
                        }
                    }
                    .onChange(of: selectedRecurringPaymentID) { _, value in
                        let linkedID = transaction.recurringPaymentId ?? ""
                        if value != linkedID { link(transaction, to: value) }
                    }
                } header: {
                    Text("Subscription")
                } footer: {
                    Text("Link imported and regular payments to the recurring bill they fulfill.")
                }
                Section {
                    if isEditing {
                        Button("Save", systemImage: "checkmark") { save(transaction) }
                        Button("Cancel", role: .cancel) { isEditing = false }
                    } else {
                        Button("Edit", systemImage: "pencil") {
                            editedTitle = transaction.title
                            editedCategory = transaction.category ?? ""
                            isEditing = true
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
        }
        .navigationTitle("Transaction")
        .onAppear { selectedRecurringPaymentID = transactions.first?.recurringPaymentId ?? "" }
        .confirmationDialog("Delete this transaction?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let transaction = transactions.first { delete(transaction) } }
        }
    }

    private func compatiblePayments(for transaction: CachedTransaction) -> [RecurringPayment] {
        recurringPayments.filter {
            $0.currency == transaction.currency && ($0.accountId == nil || $0.accountId == transaction.accountId)
        }
    }

    private func link(_ transaction: CachedTransaction, to paymentID: String) {
        let linkedID = paymentID.isEmpty ? nil : paymentID
        transaction.recurringPaymentId = linkedID
        transaction.updatedAt = ISO8601DateFormatter().string(from: Date())
        context.insert(PendingMutation(
            entityId: transaction.id, action: "upsert", newDescription: nil, newCategory: nil,
            newRecurringPaymentId: linkedID, updatesRecurringPayment: true, baseVersion: transaction.version
        ))
        try? context.save()
    }

    private func save(_ transaction: CachedTransaction) {
        let title = editedTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let category = editedCategory.trimmingCharacters(in: .whitespaces)
        transaction.title = title
        transaction.category = category.isEmpty ? nil : category
        context.insert(PendingMutation(entityId: transaction.id, action: "upsert", newDescription: title, newCategory: category.isEmpty ? nil : category, baseVersion: transaction.version))
        try? context.save()
        isEditing = false
    }

    private func delete(_ transaction: CachedTransaction) {
        context.insert(PendingMutation(entityId: transaction.id, action: "delete", newDescription: nil, newCategory: nil, baseVersion: transaction.version))
        context.delete(transaction)
        try? context.save()
        dismiss()
    }

    private func money(_ amount: Int, _ currency: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
    }
}
