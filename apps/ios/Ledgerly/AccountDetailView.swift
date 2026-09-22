import SwiftData
import SwiftUI

struct AccountDetailView: View {
    let accountID: String
    @Query private var accounts: [CachedAccount]
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]

    init(accountID: String) {
        self.accountID = accountID
        let id = accountID
        _accounts = Query(filter: #Predicate<CachedAccount> { $0.id == id })
        _transactions = Query(filter: #Predicate<CachedTransaction> { $0.accountId == id }, sort: \CachedTransaction.bookedAt, order: .reverse)
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
                        ContentUnavailableView("No transactions", systemImage: "tray")
                    }
                }
            }
        }
        .navigationTitle(accounts.first?.name ?? "Account")
        .navigationBarTitleDisplayMode(.large)
    }

    private func money(_ amount: Int, _ currency: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
    }
}
