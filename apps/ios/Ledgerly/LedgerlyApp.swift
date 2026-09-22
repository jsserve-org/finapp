import SwiftData
import SwiftUI
import Observation

@main
struct LedgerlyApp: App {
    @State private var session = SessionController()
    var body: some Scene {
        WindowGroup {
            if session.isAuthenticated { RootTabView().environment(session) }
            else { LoginView().environment(session) }
        }
            .modelContainer(for: [CachedAccount.self, CachedTransaction.self, SyncSetting.self])
    }
}

@MainActor @Observable final class SessionController {
    var isAuthenticated = KeychainStore().token() != nil
    func complete(_ response: AuthResponse) {
        KeychainStore().saveToken(response.token)
        UserDefaults.standard.set(response.context.apiUrl, forKey: "ledgerly.apiURL")
        UserDefaults.standard.set(response.context.convexUrl, forKey: "ledgerly.convexURL")
        UserDefaults.standard.set(response.user.username, forKey: "ledgerly.username")
        UserDefaults.standard.set(response.context.syncSessionId, forKey: "ledgerly.syncSessionId")
        isAuthenticated = true
    }
    func logout() {
        Task { try? await APIClient.shared.logout() }
        KeychainStore().deleteToken()
        isAuthenticated = false
    }
}

private struct LoginView: View {
    @Environment(SessionController.self) private var session
    @State private var apiURL = UserDefaults.standard.string(forKey: "ledgerly.apiURL") ?? "http://localhost:3000"
    @State private var convexURL = UserDefaults.standard.string(forKey: "ledgerly.convexURL") ?? "http://localhost:3210"
    @State private var username = ""
    @State private var password = ""
    @State private var registration = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        ZStack {
            LedgerlyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill").font(.system(size: 58)).foregroundStyle(.mint)
                    Text(registration ? "Create account" : "Welcome back").font(.largeTitle.bold())
                    Text("Connect securely to your Ledgerly server.").foregroundStyle(.secondary)
                    Group {
                        TextField("API endpoint", text: $apiURL).textContentType(.URL).textInputAutocapitalization(.never).keyboardType(.URL)
                        TextField("Convex endpoint", text: $convexURL).textContentType(.URL).textInputAutocapitalization(.never).keyboardType(.URL)
                        TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never)
                        SecureField("Password (10+ characters)", text: $password).textContentType(registration ? .newPassword : .password)
                    }.padding(15).background(.ultraThinMaterial, in: .rect(cornerRadius: 15))
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button { Task { await submit() } } label: {
                        Group { if working { ProgressView() } else { Text(registration ? "Create account" : "Log in").fontWeight(.bold) } }.frame(maxWidth: .infinity).padding(15)
                    }.buttonStyle(.borderedProminent).tint(.mint).disabled(working || username.count < 3 || password.count < 10)
                    Button(registration ? "Already have an account? Log in" : "Need an account? Register") { registration.toggle(); error = nil }.frame(maxWidth: .infinity)
                }.padding(28).frame(maxWidth: 520)
            }
        }.preferredColorScheme(.dark)
    }

    private func submit() async {
        guard let api = URL(string: apiURL), let convex = URL(string: convexURL), ["http", "https"].contains(api.scheme), ["http", "https"].contains(convex.scheme) else { error = "Enter valid HTTP(S) endpoint URLs."; return }
        working = true; error = nil
        UserDefaults.standard.set(api.absoluteString, forKey: "ledgerly.apiURL")
        do {
            if let response = try await APIClient.shared.authenticate(username: username, password: password, convexURL: convex, register: registration) { session.complete(response) }
            else { registration = false; error = "Account created. Log in to continue." }
        } catch APIError.http(let status) { error = status == 401 ? "Invalid username or password." : "Server rejected the request (\(status))." }
        catch { error = "Could not reach the server." }
        working = false
    }
}

private struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Overview", systemImage: "rectangle.grid.2x2.fill") {
                DashboardView()
            }

            Tab("Accounts", systemImage: "building.columns.fill") {
                AccountsTabView()
            }

            Tab("Insights", systemImage: "chart.bar.xaxis") {
                InsightsTabView()
            }

            Tab("Activity", systemImage: "list.bullet.rectangle.portrait.fill") {
                ActivityTabView()
            }

            Tab("Settings", systemImage: "person.crop.circle.fill") {
                NavigationStack { SettingsView() }
            }
        }
        .tint(.mint)
        .preferredColorScheme(.dark)
    }
}

private struct AccountsTabView: View {
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]

    private var total: Int { accounts.reduce(0) { $0 + $1.amountMinor } }

    var body: some View {
        NavigationStack {
            ZStack {
                LedgerlyBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        Text("ALL ACCOUNTS")
                            .font(.caption.bold())
                            .tracking(2)
                            .foregroundStyle(.mint)

                        Text(money(total, accounts.first?.currency ?? "USD"))
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())

                        Text("Across \(accounts.count) connected account\(accounts.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                        ForEach(accounts) { account in
                            NavigationLink {
                                AccountDetailView(accountID: account.id)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: accountSymbol(account))
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.mint)
                                        .frame(width: 46, height: 46)
                                        .background(.mint.opacity(0.12), in: .rect(cornerRadius: 15))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(account.name).font(.headline)
                                        Text("\(account.institution) · \(account.displayKind)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)
                                    Text(money(account.amountMinor, account.currency))
                                        .fontWeight(.semibold)
                                }
                                .padding(16)
                                .ledgerlyGlass(cornerRadius: 20)
                            }
                            .buttonStyle(.plain)
                        }

                        if accounts.isEmpty {
                            ContentUnavailableView(
                                "No accounts yet",
                                systemImage: "building.columns",
                                description: Text("Connect an account, then pull to sync from Overview.")
                            )
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.top, 56)
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func accountSymbol(_ account: CachedAccount) -> String {
        switch account.kind {
        case "checking": "creditcard.fill"
        case "savings": "banknote.fill"
        case "credit": "creditcard.trianglebadge.exclamationmark"
        case "investment": "chart.line.uptrend.xyaxis"
        default: "wallet.bifold.fill"
        }
    }
}

private struct InsightsTabView: View {
    @Query private var accounts: [CachedAccount]
    @Query private var transactions: [CachedTransaction]

    private var totalBalance: Int { accounts.reduce(0) { $0 + $1.amountMinor } }
    private var inflow: Int {
        transactions.filter { $0.amountMinor > 0 }.reduce(0) { $0 + $1.amountMinor }
    }
    private var outflow: Int {
        abs(transactions.filter { $0.amountMinor < 0 }.reduce(0) { $0 + $1.amountMinor })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LedgerlyBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("YOUR MONEY AT A GLANCE")
                            .font(.caption.bold())
                            .tracking(2)
                            .foregroundStyle(.mint)

                        insightCard("Net worth", value: totalBalance, symbol: "sum", tint: .mint)
                        HStack(spacing: 12) {
                            insightCard("Money in", value: inflow, symbol: "arrow.down.left", tint: .mint)
                            insightCard("Money out", value: outflow, symbol: "arrow.up.right", tint: .orange)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Snapshot", systemImage: "chart.pie.fill")
                                .font(.headline)
                            Text(transactions.isEmpty
                                 ? "Your trends will appear after the first sync."
                                 : "Based on \(transactions.count) saved transaction\(transactions.count == 1 ? "" : "s").")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .ledgerlyGlass(cornerRadius: 22)
                    }
                    .padding(20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func insightCard(_ title: String, value: Int, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(money(value, accounts.first?.currency ?? "USD"))
                .font(.title3.bold())
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .ledgerlyGlass(cornerRadius: 22)
    }
}

private struct ActivityTabView: View {
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]

    var body: some View {
        NavigationStack {
            ZStack {
                LedgerlyBackground()

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(transactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transactionID: transaction.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: transaction.amountMinor > 0 ? "arrow.down.left" : "arrow.up.right")
                                        .font(.callout.bold())
                                        .foregroundStyle(transaction.amountMinor > 0 ? .mint : .orange)
                                        .frame(width: 42, height: 42)
                                        .background(.white.opacity(0.07), in: .rect(cornerRadius: 14))

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(transaction.title).fontWeight(.semibold)
                                        Text(transaction.category ?? "Uncategorized")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(money(transaction.amountMinor, transaction.currency))
                                            .foregroundStyle(transaction.amountMinor > 0 ? .mint : .primary)
                                        if transaction.pending {
                                            Text("Pending").font(.caption2).foregroundStyle(.orange)
                                        }
                                    }
                                }
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)

                            if transaction.id != transactions.last?.id {
                                Divider().overlay(.white.opacity(0.08))
                            }
                        }

                        if transactions.isEmpty {
                            ContentUnavailableView(
                                "No activity yet",
                                systemImage: "list.bullet.rectangle",
                                description: Text("Transactions will appear here after you sync.")
                            )
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.top, 80)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct LedgerlyBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.03, green: 0.22, blue: 0.16)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

private func money(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency))
}
