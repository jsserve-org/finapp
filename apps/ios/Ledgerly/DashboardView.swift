import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionController.self) private var session
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var sync = SyncController()
    @State private var showingNewAccount = false

    private var ownedAccounts: [CachedAccount] { accounts.filter(\.isIncludedInNetWorth) }
    private var trackedCards: [CachedAccount] { accounts.filter { !$0.isIncludedInNetWorth } }

    var body: some View {
        NavigationStack {
            List {
                accountSection("Your accounts", accounts: ownedAccounts)
                if !trackedCards.isEmpty { accountSection("Cards you track", accounts: trackedCards) }
                if accounts.isEmpty { emptyState }
            }
            .listStyle(.insetGrouped)
            .refreshable { if session.isAuthenticated { await sync.refresh(context: context) } }
            .navigationTitle("Overview")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { NativeInsightsView() } label: {
                        Label("Insights", systemImage: AppIcon.insights)
                    }
                    Button("Add account", systemImage: "plus") { showingNewAccount = true }
                }
            }
            .sheet(isPresented: $showingNewAccount) { NewAccountView() }
            .task { if session.isAuthenticated { await sync.refresh(context: context) } }
        }
    }

    @ViewBuilder
    private func accountSection(_ title: String, accounts: [CachedAccount]) -> some View {
        if !accounts.isEmpty {
            Section(title) {
                ForEach(accounts) { account in
                    NavigationLink { AccountDetailView(accountID: account.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: accountSymbol(account)).ledgerlyIcon().frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(account.name).font(.headline)
                                Text("\(account.institution) · \(account.displayKind)")
                                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(money(account.amountMinor, account.currency))
                                .font(.body.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.72)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No accounts yet", systemImage: AppIcon.account)
        } description: {
            Text("Add your bank account, cash, or a card you use for someone else.")
        } actions: {
            Button("Add account", systemImage: "plus") { showingNewAccount = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func accountSymbol(_ account: CachedAccount) -> String {
        switch account.kind {
        case "checking": "creditcard.fill"
        case "savings": "banknote.fill"
        case "credit": "creditcard.trianglebadge.exclamationmark"
        case "sharedCredit": "person.crop.circle.badge.checkmark"
        case "investment": "chart.line.uptrend.xyaxis"
        default: AppIcon.cash
        }
    }

    private func money(_ amount: Int, _ currency: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: currency).presentation(.isoCode))
    }
}
