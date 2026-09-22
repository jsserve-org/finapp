import SwiftData
import SwiftUI

struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let accountID: String
    @Query private var accounts: [CachedAccount]
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]
    @Query private var recurringPayments: [RecurringPayment]
    @State private var confirmingDelete = false

    init(accountID: String) {
        self.accountID = accountID
        let id = accountID
        _accounts = Query(filter: #Predicate<CachedAccount> { $0.id == id })
        _transactions = Query(filter: #Predicate<CachedTransaction> { $0.accountId == id }, sort: \CachedTransaction.bookedAt, order: .reverse)
        _recurringPayments = Query(filter: #Predicate<RecurringPayment> { $0.accountId == id })
    }

    var body: some View {
        List {
            if let account = accounts.first {
                Section("Account") {
                    LabeledContent("Balance") { Text(money(account.amountMinor, account.currency)).font(.title2.bold()) }
                    LabeledContent("Institution", value: account.institution)
                    LabeledContent("Type", value: account.displayKind)
                }
                Section("Transactions") {
                    ForEach(transactions) { transaction in
                        NavigationLink { TransactionDetailView(transactionID: transaction.id) } label: {
                            LabeledContent {
                                Text(money(transaction.amountMinor, transaction.currency))
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(transaction.title).font(.headline)
                                    Text(transaction.category ?? "Uncategorized").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if transactions.isEmpty {
                        ContentUnavailableView("No transactions", systemImage: AppIcon.empty)
                    }
                }
            }
        }
        .navigationTitle(accounts.first?.name ?? "Account")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete account", systemImage: "trash", role: .destructive) { confirmingDelete = true }
            }
        }
        .confirmationDialog(
            "Delete this account?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account and its activity", role: .destructive) { deleteAccount() }
        } message: {
            Text("This removes the account, its transactions, and linked recurring bills from this device and the sync server.")
        }
    }

    private func money(_ amount: Int, _ currency: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
    }

    private func deleteAccount() {
        guard let account = accounts.first else { return }
        let accountID = account.id
        context.insert(PendingAccountMutation(entityId: accountID, action: "delete"))
        transactions.forEach(context.delete)
        recurringPayments.forEach(context.delete)
        context.delete(account)
        try? context.save()
        dismiss()
    }
}
