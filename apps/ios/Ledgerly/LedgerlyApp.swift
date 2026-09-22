import SwiftData
import SwiftUI
import Observation

@main
struct LedgerlyApp: App {
    @State private var session = SessionController()
    var body: some Scene {
        WindowGroup {
            if session.canUseApp { RootTabView().environment(session) }
            else { LoginView().environment(session) }
        }
            .modelContainer(for: [CachedAccount.self, CachedTransaction.self, SyncSetting.self, PendingMutation.self])
    }
}

@MainActor @Observable final class SessionController {
    var isAuthenticated = KeychainStore().token() != nil
    var localOnly = UserDefaults.standard.bool(forKey: "ledgerly.localOnly")
    var canUseApp: Bool { isAuthenticated || localOnly }
    func complete(_ response: AuthResponse) {
        KeychainStore().saveToken(response.token)
        UserDefaults.standard.set(response.context.apiUrl, forKey: "ledgerly.apiURL")
        UserDefaults.standard.set(response.context.convexUrl, forKey: "ledgerly.convexURL")
        UserDefaults.standard.set(response.user.username, forKey: "ledgerly.username")
        UserDefaults.standard.set(response.context.syncSessionId, forKey: "ledgerly.syncSessionId")
        UserDefaults.standard.set(false, forKey: "ledgerly.localOnly")
        localOnly = false
        isAuthenticated = true
    }
    func continueLocally() {
        UserDefaults.standard.set(true, forKey: "ledgerly.localOnly")
        localOnly = true
    }
    func logout() {
        Task { try? await APIClient.shared.logout() }
        KeychainStore().deleteToken()
        isAuthenticated = false
    }
    func configureSync() {
        UserDefaults.standard.set(false, forKey: "ledgerly.localOnly")
        localOnly = false
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
    @State private var registrationEnabled = true

    var body: some View {
        ZStack {
            LedgerlyBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("LEDGERLY").font(.caption.bold()).tracking(2).foregroundStyle(.secondary)
                    Text(registration ? "Create a sync account" : "Your money, on your device").font(.largeTitle.bold())
                    Text(registration ? "Create credentials for your self-hosted server." : "Start locally, or sign in to sync across devices.").foregroundStyle(.secondary)
                    if !registration {
                        Button { session.continueLocally() } label: {
                            Label("Continue on this iPhone", systemImage: "iphone").fontWeight(.semibold).frame(maxWidth: .infinity).padding(10)
                        }.buttonStyle(.borderedProminent)
                        HStack { Rectangle().frame(height: 1); Text("or connect a server").font(.caption); Rectangle().frame(height: 1) }.foregroundStyle(.tertiary)
                    }
                    Group {
                        TextField("API endpoint", text: $apiURL).textContentType(.URL).textInputAutocapitalization(.never).keyboardType(.URL)
                        TextField("Convex endpoint", text: $convexURL).textContentType(.URL).textInputAutocapitalization(.never).keyboardType(.URL)
                        TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never)
                        SecureField("Password (10+ characters)", text: $password).textContentType(registration ? .newPassword : .password)
                    }.padding(15).background(.ultraThinMaterial, in: .rect(cornerRadius: 15))
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button { Task { await submit() } } label: {
                        Group { if working { ProgressView() } else { Text(registration ? "Create account" : "Log in").fontWeight(.bold) } }.frame(maxWidth: .infinity).padding(15)
                    }.buttonStyle(.bordered).disabled(working || username.count < 3 || password.count < 10)
                    if registration || registrationEnabled {
                        Button(registration ? "Already have an account? Log in" : "Need an account? Register") { registration.toggle(); error = nil }.frame(maxWidth: .infinity)
                    }
                }.padding(28).frame(maxWidth: 520)
            }
        }.preferredColorScheme(.dark).task { await loadServerConfig() }
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

    private func loadServerConfig() async {
        UserDefaults.standard.set(apiURL, forKey: "ledgerly.apiURL")
        if let config = try? await APIClient.shared.serverConfig() {
            registrationEnabled = config.registrationEnabled
            if convexURL == "http://localhost:3210" { convexURL = config.convexUrl }
        }
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
        .tint(Color(red: 0.48, green: 0.66, blue: 1.0))
        .preferredColorScheme(.dark)
    }
}

private struct AccountsTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var showingNewAccount = false

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
                            .foregroundStyle(.blue)

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
                                        .foregroundStyle(.blue)
                                        .frame(width: 46, height: 46)
                                        .background(.blue.opacity(0.12), in: .rect(cornerRadius: 15))

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
                                description: Text("Create an account on this device. Sync is optional.")
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingNewAccount = true } label: { Image(systemName: "plus") } } }
            .sheet(isPresented: $showingNewAccount) { NewAccountView() }
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
                            .foregroundStyle(.blue)

                        insightCard("Net worth", value: totalBalance, symbol: "sum", tint: .blue)
                        HStack(spacing: 12) {
                            insightCard("Money in", value: inflow, symbol: "arrow.down.left", tint: .blue)
                            insightCard("Money out", value: outflow, symbol: "arrow.up.right", tint: .orange)
                        }

                        VStack(alignment: .leading, spacing: 14) {
                            Label("Snapshot", systemImage: "chart.pie.fill")
                                .font(.headline)
                            Text(transactions.isEmpty
                                 ? "Add transactions to see spending patterns."
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
                                        .foregroundStyle(transaction.amountMinor > 0 ? .blue : .orange)
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
                                            .foregroundStyle(transaction.amountMinor > 0 ? .blue : .primary)
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

struct LedgerlyBackground: View {
    var body: some View {
        Color(red: 0.045, green: 0.047, blue: 0.055).ignoresSafeArea()
    }
}

struct NewAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var institution = ""
    @State private var kind = "checking"
    @State private var balance = ""
    @State private var currency = "USD"
    private let kinds = [("checking", "Checking"), ("savings", "Savings"), ("credit", "Credit card"), ("investment", "Investment"), ("cash", "Cash")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    TextField("Institution (optional)", text: $institution)
                    Picker("Type", selection: $kind) { ForEach(kinds, id: \.0) { Text($0.1).tag($0.0) } }
                }
                Section("Opening balance") {
                    TextField("0.00", text: $balance).keyboardType(.decimalPad)
                    TextField("Currency", text: $currency).textInputAutocapitalization(.characters)
                }
                Section { Text("This account is saved locally. You can enable sync later in Settings.").font(.caption).foregroundStyle(.secondary) }
            }
            .navigationTitle("New account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }.preferredColorScheme(.dark)
    }

    private func save() {
        let decimal = Decimal(string: balance.replacingOccurrences(of: ",", with: ".")) ?? 0
        let minor = NSDecimalNumber(decimal: decimal * 100).intValue
        context.insert(CachedAccount(name: name.trimmingCharacters(in: .whitespaces), institution: institution.trimmingCharacters(in: .whitespaces).isEmpty ? "Manual" : institution.trimmingCharacters(in: .whitespaces), kind: kind, amountMinor: minor, currency: currency.uppercased()))
        try? context.save()
        dismiss()
    }
}

private func money(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency))
}
