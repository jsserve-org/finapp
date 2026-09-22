import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    let transactionID: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var transactions: [CachedTransaction]
    @State private var editedTitle = ""
    @State private var editedCategory = ""
    @State private var isEditing = false
    @State private var showDeleteConfirm = false

    init(transactionID: String) {
        self.transactionID = transactionID
        let id = transactionID
        _transactions = Query(filter: #Predicate<CachedTransaction> { $0.id == id })
    }

    var body: some View {
        Form {
            if let transaction = transactions.first {
                Section("Transaction") {
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
        .confirmationDialog("Delete this transaction?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let transaction = transactions.first { delete(transaction) } }
        }
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
