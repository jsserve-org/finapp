import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]
    @State private var sync = SyncController()
    private var total: Int { accounts.reduce(0) { $0 + $1.amountMinor } }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.03, green: 0.22, blue: 0.16)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Text("OVERVIEW").font(.caption.bold()).tracking(2).foregroundStyle(.mint)
                        Text("Good morning").font(.largeTitle.bold()).foregroundStyle(.white)
                        if sync.isOffline { Label("Offline · showing saved data", systemImage: "wifi.slash").font(.caption).foregroundStyle(.orange) }
                        balanceCard
                        section("Accounts")
                        ForEach(accounts) { account in accountRow(account) }
                        section("Recent activity")
                        ForEach(transactions.prefix(8)) { transaction in transactionRow(transaction) }
                        if accounts.isEmpty { ContentUnavailableView("No accounts yet", systemImage: "building.columns", description: Text("Run the demo automation, then pull to sync.")) .foregroundStyle(.white.opacity(0.8)) }
                    }.padding(20)
                }.refreshable { await sync.refresh(context: context) }
            }.task { await sync.refresh(context: context) }
        }.preferredColorScheme(.dark)
    }

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOTAL BALANCE").font(.caption.bold()).tracking(1.5).foregroundStyle(.secondary)
            Text(money(total, accounts.first?.currency ?? "USD")).font(.system(size: 42, weight: .bold, design: .rounded))
            Text("\(accounts.count) connected account\(accounts.count == 1 ? "" : "s")").foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24).ledgerlyGlass(cornerRadius: 28)
    }

    private func section(_ title: String) -> some View { Text(title).font(.title3.bold()).foregroundStyle(.white).padding(.top, 8) }
    private func accountRow(_ item: CachedAccount) -> some View {
        HStack { VStack(alignment: .leading) { Text(item.name).font(.headline); Text(item.institution).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(money(item.amountMinor, item.currency)).fontWeight(.semibold) }
            .padding(18).ledgerlyGlass(cornerRadius: 20)
    }
    private func transactionRow(_ item: CachedTransaction) -> some View {
        HStack(spacing: 12) { Image(systemName: "arrow.up.arrow.down").frame(width: 42, height: 42).background(.mint.opacity(0.15), in: .rect(cornerRadius: 14)); VStack(alignment: .leading) { Text(item.title).fontWeight(.semibold); Text(item.category ?? "Uncategorized").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(money(item.amountMinor, item.currency)).foregroundStyle(item.amountMinor > 0 ? .mint : .primary) }.padding(.vertical, 5)
    }
    private func money(_ amount: Int, _ currency: String) -> String { (Double(amount) / 100).formatted(.currency(code: currency)) }
}

private extension View {
    @ViewBuilder func ledgerlyGlass(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius)) }
        else { self.background(.ultraThinMaterial, in: .rect(cornerRadius: cornerRadius)) }
    }
}
