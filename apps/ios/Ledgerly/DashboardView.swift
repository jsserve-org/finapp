import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionController.self) private var session
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]
    @State private var sync = SyncController()
    @State private var path = NavigationPath()
    @State private var showingNewAccount = false

    private var balances: [(currency: String, amount: Int)] {
        let grouped = Dictionary(grouping: accounts, by: \.currency)
        return grouped.map { (currency: $0.key, amount: $0.value.reduce(0) { $0 + $1.amountMinor }) }
            .sorted { $0.currency < $1.currency }
    }
    private var pendingCount: Int {
        ((try? context.fetchCount(FetchDescriptor<PendingMutation>())) ?? 0) + ((try? context.fetchCount(FetchDescriptor<PendingAccountMutation>())) ?? 0)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("Balance") { balanceSummary }
                Section {
                    ForEach(accounts) { account in
                        NavigationLink(value: account.id) { accountRow(account) }
                    }
                    if accounts.isEmpty { emptyState }
                } header: {
                    HStack {
                        Text("Accounts")
                        Spacer()
                        Button("Add", systemImage: "plus") { showingNewAccount = true }
                    }
                }
                if !transactions.isEmpty {
                    Section("Recent activity") {
                        ForEach(transactions.prefix(8)) { transaction in
                            NavigationLink(value: transaction.id) { transactionRow(transaction) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { if session.isAuthenticated { await sync.refresh(context: context) } }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: String.self) { id in
                if let account = accounts.first(where: { $0.id == id }) {
                    AccountDetailView(accountID: account.id)
                } else if let transaction = transactions.first(where: { $0.id == id }) {
                    TransactionDetailView(transactionID: transaction.id)
                } else {
                    ContentUnavailableView("Not found", systemImage: "questionmark.circle")
                }
            }
            .sheet(isPresented: $showingNewAccount) { NewAccountView() }
            .task { if session.isAuthenticated { await sync.refresh(context: context) } }
        }
    }

    private var balanceSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if balances.isEmpty {
                Text(money(0, SupportedCurrency.defaultCode))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
            } else {
                ForEach(balances, id: \.currency) { balance in
                    Text(money(balance.amount, balance.currency))
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                }
            }
            HStack(spacing: 8) {
                Image(systemName: session.localOnly ? "iphone" : (sync.isOffline ? "wifi.slash" : "checkmark.icloud"))
                Text(session.localOnly ? "Saved on this iPhone" : (sync.isOffline ? "Offline" : "Up to date"))
                if sync.isSyncing { ProgressView().controlSize(.small) }
                if let syncedAt = sync.lastSyncedAt {
                    Text("· synced \(syncedAt.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            if pendingCount > 0 {
                Text("\(pendingCount) change\(pendingCount == 1 ? "" : "s") waiting to sync")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wallet.bifold").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Start with an account").font(.headline)
            Text("Add a bank, card, cash, or savings account. It stays on this device until you enable sync.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Create account") { showingNewAccount = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
    }

    private func accountRow(_ item: CachedAccount) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.headline)
                Text("\(item.institution) · \(item.displayKind)").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(money(item.amountMinor, item.currency)).fontWeight(.semibold)
        }
        .padding(.vertical, 4)
    }

    private func transactionRow(_ item: CachedTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down").foregroundStyle(.secondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).fontWeight(.semibold)
                Text(item.category ?? "Uncategorized").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(money(item.amountMinor, item.currency)).foregroundStyle(item.amountMinor > 0 ? .blue : .primary)
                if item.pending { Text("Pending").font(.footnote).foregroundStyle(.orange) }
            }
        }
        .padding(.vertical, 4)
    }

    private func money(_ amount: Int, _ currency: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
    }
}
