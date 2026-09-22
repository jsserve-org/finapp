import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]
    @State private var sync = SyncController()
    @State private var path = NavigationPath()

    private var total: Int { accounts.reduce(0) { $0 + $1.amountMinor } }
    private var pendingCount: Int {
        (try? context.fetchCount(FetchDescriptor<PendingMutation>())) ?? 0
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.03, green: 0.22, blue: 0.16)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Text("OVERVIEW").font(.caption.bold()).tracking(2).foregroundStyle(.mint)
                        Text(greeting).font(.largeTitle.bold()).foregroundStyle(.white)
                        if sync.isOffline { offlineBanner }
                        balanceCard
                        section("Accounts")
                        ForEach(accounts) { account in
                            NavigationLink(value: account.id) {
                                accountRow(account)
                            }.buttonStyle(.plain)
                        }
                        section("Recent activity")
                        ForEach(transactions.prefix(8)) { transaction in
                            NavigationLink(value: transaction.id) {
                                transactionRow(transaction)
                            }.buttonStyle(.plain)
                        }
                        if accounts.isEmpty { emptyState }
                    }.padding(20)
                }.refreshable { await sync.refresh(context: context) }
            }
            .navigationDestination(for: String.self) { id in
                if let account = accounts.first(where: { $0.id == id }) {
                    AccountDetailView(accountID: account.id)
                } else if let transaction = transactions.first(where: { $0.id == id }) {
                    TransactionDetailView(transactionID: transaction.id)
                } else {
                    ContentUnavailableView("Not found", systemImage: "questionmark.circle")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { ConnectionHealthView() } label: { Image(systemName: "antenna.radiowaves.left.and.right") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
            }
            .task { await sync.refresh(context: context) }
        }.preferredColorScheme(.dark)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    private var offlineBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Offline · showing saved data", systemImage: "wifi.slash").font(.caption).foregroundStyle(.orange)
            if pendingCount > 0 {
                Label("\(pendingCount) edit\(pendingCount == 1 ? "" : "s") waiting to sync", systemImage: "tray.and.arrow.up").font(.caption2).foregroundStyle(.secondary)
            }
            if let lastError = sync.lastError {
                Text(lastError).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .ledgerlyGlass(cornerRadius: 16)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOTAL BALANCE").font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
            Text(money(total, accounts.first?.currency ?? "USD")).font(.system(size: 42, weight: .bold, design: .rounded))
            HStack(spacing: 8) {
                Text("\(accounts.count) connected account\(accounts.count == 1 ? "" : "s")").foregroundStyle(.secondary)
                if sync.isSyncing { ProgressView().controlSize(.small) }
                if let syncedAt = sync.lastSyncedAt {
                    Text("· synced \(syncedAt.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24).ledgerlyGlass(cornerRadius: 28)
    }

    private var emptyState: some View {
        ContentUnavailableView("No accounts yet", systemImage: "building.columns", description: Text("Run the demo automation, then pull to sync.")).foregroundStyle(.white.opacity(0.8))
    }

    private func section(_ title: String) -> some View { Text(title).font(.title3.bold()).foregroundStyle(.white).padding(.top, 8) }

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
            Image(systemName: "arrow.up.arrow.down").frame(width: 42, height: 42).background(.mint.opacity(0.15), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading) {
                Text(item.title).fontWeight(.semibold)
                Text(item.category ?? "Uncategorized").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(money(item.amountMinor, item.currency)).foregroundStyle(item.amountMinor > 0 ? .mint : .primary)
                if item.pending { Text("Pending").font(.caption2).foregroundStyle(.orange) }
            }
        }.padding(.vertical, 5)
    }

    private func money(_ amount: Int, _ currency: String) -> String { (Double(amount) / 100).formatted(.currency(code: currency)) }
}

extension View {
    @ViewBuilder func ledgerlyGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius)) }
        else { self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius)) }
    }
}
