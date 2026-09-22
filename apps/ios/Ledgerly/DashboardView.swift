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

    private var total: Int { accounts.reduce(0) { $0 + $1.amountMinor } }
    private var pendingCount: Int {
        ((try? context.fetchCount(FetchDescriptor<PendingMutation>())) ?? 0) + ((try? context.fetchCount(FetchDescriptor<PendingAccountMutation>())) ?? 0)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color(red: 0.045, green: 0.047, blue: 0.055).ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        balanceCard
                        HStack {
                            section("Accounts")
                            Spacer()
                            Button { showingNewAccount = true } label: { Label("Add", systemImage: "plus") }
                                .font(.subheadline.weight(.semibold))
                        }
                        ForEach(accounts) { account in
                            NavigationLink(value: account.id) {
                                accountRow(account)
                            }.buttonStyle(.plain)
                        }
                        if !transactions.isEmpty {
                            section("Recent activity")
                            ForEach(transactions.prefix(8)) { transaction in
                                NavigationLink(value: transaction.id) { transactionRow(transaction) }.buttonStyle(.plain)
                            }
                        }
                        if accounts.isEmpty { emptyState }
                    }.padding(.horizontal, 20).padding(.bottom, 32)
                }.refreshable { if session.isAuthenticated { await sync.refresh(context: context) } }
            }
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
        }.preferredColorScheme(.dark)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Net balance").font(.subheadline).foregroundStyle(.secondary)
            Text(money(total, accounts.first?.currency ?? "USD")).font(.system(size: 40, weight: .semibold, design: .rounded))
            HStack(spacing: 8) {
                Image(systemName: session.localOnly ? "iphone" : (sync.isOffline ? "wifi.slash" : "checkmark.icloud"))
                Text(session.localOnly ? "Saved on this iPhone" : (sync.isOffline ? "Offline" : "Up to date"))
                if sync.isSyncing { ProgressView().controlSize(.small) }
                if let syncedAt = sync.lastSyncedAt {
                    Text("· synced \(syncedAt.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary)
                }
            }.font(.caption).foregroundStyle(.secondary)
            if pendingCount > 0 { Text("\(pendingCount) change\(pendingCount == 1 ? "" : "s") waiting to sync").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).ledgerlyGlass(cornerRadius: 22)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "wallet.bifold").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Start with an account").font(.headline)
            Text("Add a bank, card, cash, or savings account. It stays on this device until you enable sync.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Create account") { showingNewAccount = true }.buttonStyle(.borderedProminent)
        }.frame(maxWidth: .infinity).padding(.vertical, 34)
    }

    private func section(_ title: String) -> some View { Text(title).font(.title3.bold()).foregroundStyle(.primary).padding(.top, 8) }

    private func accountRow(_ item: CachedAccount) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.name).font(.headline)
                Text("\(item.institution) · \(item.displayKind)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(money(item.amountMinor, item.currency)).fontWeight(.semibold)
        }
        .padding(18).ledgerlyGlass(cornerRadius: 20)
    }

    private func transactionRow(_ item: CachedTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.up.arrow.down").frame(width: 42, height: 42).background(.white.opacity(0.07), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading) {
                Text(item.title).fontWeight(.semibold)
                Text(item.category ?? "Uncategorized").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(money(item.amountMinor, item.currency)).foregroundStyle(item.amountMinor > 0 ? Color(red: 0.48, green: 0.66, blue: 1.0) : .primary)
                if item.pending { Text("Pending").font(.caption2).foregroundStyle(.orange) }
            }
        }.padding(.vertical, 5)
    }

    private func money(_ amount: Int, _ currency: String) -> String { (Double(amount) / 100).formatted(.currency(code: currency)) }
}

extension View {
    @ViewBuilder func ledgerlyGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius)) }
        else { self.background(Color.white.opacity(0.055), in: .rect(cornerRadius: cornerRadius)) }
    }
}
