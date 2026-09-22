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
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.03, green: 0.22, blue: 0.16)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                if let account = accounts.first {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(account.name).font(.title.bold()).foregroundStyle(.white)
                            Text("\(account.institution) · \(account.displayKind)").foregroundStyle(.secondary)
                            Text(money(account.amountMinor, account.currency)).font(.system(size: 36, weight: .bold, design: .rounded))
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(24).ledgerlyGlass(cornerRadius: 28)

                        Text("Transactions").font(.title3.bold()).foregroundStyle(.white)
                        ForEach(transactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transactionID: transaction.id)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(transaction.title).fontWeight(.semibold)
                                        Text(transaction.category ?? "Uncategorized").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(money(transaction.amountMinor, transaction.currency))
                                }.padding(14).ledgerlyGlass(cornerRadius: 16)
                            }.buttonStyle(.plain)
                        }
                        if transactions.isEmpty {
                            ContentUnavailableView("No transactions", systemImage: "tray")
                        }
                    }.padding(20)
                }
            }
        }.preferredColorScheme(.dark)
    }

    private func money(_ amount: Int, _ currency: String) -> String { (Double(amount) / 100).formatted(.currency(code: currency)) }
}
