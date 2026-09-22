import SwiftData
import SwiftUI

struct TransactionDetailView: View {
    let transactionID: String
    @Environment(\.modelContext) private var context
    @Query private var transactions: [CachedTransaction]

    @State private var editedTitle = ""
    @State private var editedCategory = ""
    @State private var isEditing = false
    @State private var showDeleteConfirm = false
    @State private var savedFlash = false

    init(transactionID: String) {
        self.transactionID = transactionID
        let id = transactionID
        _transactions = Query(filter: #Predicate<CachedTransaction> { $0.id == id })
    }

    private var transaction: CachedTransaction? { transactions.first }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.03, green: 0.22, blue: 0.16)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                if let transaction {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            if isEditing {
                                TextField("Description", text: $editedTitle).textFieldStyle(.roundedBorder).font(.title3.bold())
                                TextField("Category", text: $editedCategory).textFieldStyle(.roundedBorder)
                            } else {
                                Text(transaction.title).font(.title.bold()).foregroundStyle(.white)
                                Text(transaction.category ?? "Uncategorized").foregroundStyle(.secondary)
                            }
                            Text(money(transaction.amountMinor, transaction.currency)).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(transaction.amountMinor > 0 ? .mint : .white)
                            HStack(spacing: 12) {
                                if transaction.pending { Label("Pending", systemImage: "clock").font(.caption).foregroundStyle(.orange) }
                                if let date = transaction.bookedDate {
                                    Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                                }
                                Text("v\(transaction.version)").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24).ledgerlyGlass(cornerRadius: 28)

                        if savedFlash {
                            Label("Saved offline · will sync automatically", systemImage: "tray.and.arrow.up").font(.caption).foregroundStyle(.mint)
                        }

                        if isEditing {
                            Button {
                                save(transaction)
                            } label: {
                                Label("Save", systemImage: "checkmark").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).tint(.mint)
                            Button("Cancel", role: .cancel) { isEditing = false }.frame(maxWidth: .infinity)
                        } else {
                            Button {
                                editedTitle = transaction.title
                                editedCategory = transaction.category ?? ""
                                isEditing = true
                            } label: {
                                Label("Edit", systemImage: "pencil").frame(maxWidth: .infinity)
                            }.buttonStyle(.borderedProminent).tint(.mint)
                            Button("Delete", role: .destructive) { showDeleteConfirm = true }.frame(maxWidth: .infinity)
                        }
                    }.padding(20)
                }
            }
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this transaction?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let transaction { delete(transaction) } }
        }
    }

    private func save(_ transaction: CachedTransaction) {
        let newTitle = editedTitle.trimmingCharacters(in: .whitespaces)
        guard !newTitle.isEmpty else { return }
        transaction.title = newTitle
        let category = editedCategory.trimmingCharacters(in: .whitespaces)
        transaction.category = category.isEmpty ? nil : category
        context.insert(PendingMutation(entityId: transaction.id, action: "upsert", newDescription: newTitle, newCategory: category.isEmpty ? nil : category, baseVersion: transaction.version))
        try? context.save()
        isEditing = false
        savedFlash = true
        Task { try? await Task.sleep(for: .seconds(3)); savedFlash = false }
    }

    private func delete(_ transaction: CachedTransaction) {
        context.insert(PendingMutation(entityId: transaction.id, action: "delete", newDescription: nil, newCategory: nil, baseVersion: transaction.version))
        context.delete(transaction)
        try? context.save()
    }

    private func money(_ amount: Int, _ currency: String) -> String { (Double(amount) / 100).formatted(.currency(code: currency)) }
}
