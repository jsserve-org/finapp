import SwiftData
import SwiftUI

struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let accountID: String
    @Query private var accounts: [CachedAccount]
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]
    @Query private var recurringPayments: [RecurringPayment]
    @Query private var linkedHoldings: [StockHolding]
    @Query private var allAccounts: [CachedAccount]
    @State private var confirmingDelete = false
    @State private var selectedTransaction: TransactionSnapshot?
    @State private var showingMoneyIn = false
    @State private var showingMoneyOut = false
    @State private var showingTransfer = false
    @State private var showingEdit = false

    init(accountID: String) {
        self.accountID = accountID
        let id = accountID
        _accounts = Query(filter: #Predicate<CachedAccount> { $0.id == id })
        _transactions = Query(filter: #Predicate<CachedTransaction> { $0.accountId == id }, sort: \CachedTransaction.bookedAt, order: .reverse)
        _recurringPayments = Query(filter: #Predicate<RecurringPayment> { $0.accountId == id })
        _linkedHoldings = Query(filter: #Predicate<StockHolding> { $0.linkedAccountId == id })
    }

    var body: some View {
        List {
            if let account = accounts.first {
                Section("Account") {
                    LabeledContent("Balance") { Text(money(account.amountMinor, account.currency)).font(.title2.bold()) }
                    LabeledContent("Institution", value: account.institution)
                    LabeledContent("Type", value: account.displayKind)
                }
                Section("Actions") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        accountAction("Add money", symbol: "plus.circle.fill", color: .green) { showingMoneyIn = true }
                        accountAction("Spend", symbol: "minus.circle.fill", color: .red) { showingMoneyOut = true }
                        accountAction("Transfer", symbol: "arrow.left.arrow.right.circle.fill", color: .blue) { showingTransfer = true }
                        accountAction("Edit", symbol: "pencil.circle.fill", color: .secondary) { showingEdit = true }
                    }
                    .padding(.vertical, 4)
                }
                Section("Transactions") {
                    ForEach(transactions) { transaction in
                        let recurringPayment = recurringPayments.first { $0.id == transaction.recurringPaymentId }
                        let snapshot = TransactionSnapshot(
                            transaction, account: account, recurringPayment: recurringPayment,
                            transferAccount: allAccounts.first { $0.id == transaction.transferAccountId }
                        )
                        Button { selectedTransaction = snapshot } label: {
                            HStack(spacing: 12) {
                                Image(systemName: PaymentIcon.symbol(title: transaction.title, category: transaction.category, amountMinor: transaction.amountMinor))
                                    .ledgerlyIcon(color: PaymentIcon.color(amountMinor: transaction.amountMinor))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(transaction.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(PaymentIcon.directionLabel(amountMinor: transaction.amountMinor)) · \(transaction.category ?? "Uncategorized")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
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
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if transactions.isEmpty {
                        ContentUnavailableView("No transactions", systemImage: AppIcon.empty)
                    }
                }
            }
        }
        .navigationTitle(accounts.first?.name ?? "Account")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $selectedTransaction) { snapshot in
            TransactionDetailView(transaction: snapshot)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit account", systemImage: "pencil") { showingEdit = true }
                    Button("Delete account", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("Account options", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingMoneyIn) { if let account = accounts.first { AccountEntryView(account: account, direction: .moneyIn) } }
        .sheet(isPresented: $showingMoneyOut) { if let account = accounts.first { AccountEntryView(account: account, direction: .moneyOut) } }
        .sheet(isPresented: $showingTransfer) { if let account = accounts.first { AccountTransferView(source: account) } }
        .sheet(isPresented: $showingEdit) { if let account = accounts.first { EditAccountView(account: account) } }
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

    private func accountAction(_ title: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func deleteAccount() {
        guard let account = accounts.first else { return }
        let accountID = account.id
        context.insert(PendingAccountMutation(entityId: accountID, action: "delete"))
        transactions.forEach(context.delete)
        recurringPayments.forEach(context.delete)
        for holding in linkedHoldings {
            holding.linkedAccountId = nil
            holding.updatedAt = ISO8601DateFormatter().string(from: Date())
            context.insert(PendingStockMutation(entityId: holding.id, entity: "stockHolding"))
        }
        context.delete(account)
        try? context.save()
        dismiss()
    }
}
