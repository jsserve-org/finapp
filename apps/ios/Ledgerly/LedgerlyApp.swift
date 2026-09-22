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
            .modelContainer(for: [CachedAccount.self, CachedTransaction.self, SyncSetting.self, PendingMutation.self, PendingAccountMutation.self, RecurringPayment.self])
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
        catch { self.error = "Could not reach the server." }
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
    @State private var selection: RootTab = .overview

    var body: some View {
        TabView(selection: $selection) {
            Tab("Overview", systemImage: "rectangle.grid.2x2.fill", value: RootTab.overview) {
                DashboardView()
            }

            Tab("Accounts", systemImage: "building.columns.fill", value: RootTab.accounts) {
                AccountsTabView()
            }

            Tab("Insights", systemImage: "chart.bar.xaxis", value: RootTab.insights) {
                InsightsTabView()
            }

            Tab("Activity", systemImage: "list.bullet.rectangle.portrait.fill", value: RootTab.activity) {
                ActivityTabView()
            }

            Tab("Settings", systemImage: "person.crop.circle.fill", value: RootTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { LedgerlyTabBar(selection: $selection) }
        .tint(Color(red: 0.48, green: 0.66, blue: 1.0))
        .preferredColorScheme(.dark)
    }
}

private enum RootTab: String, CaseIterable, Identifiable {
    case overview, accounts, insights, activity, settings
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .overview: "rectangle.grid.2x2.fill"
        case .accounts: "building.columns.fill"
        case .insights: "chart.bar.fill"
        case .activity: "list.bullet.rectangle.portrait.fill"
        case .settings: "person.crop.circle.fill"
        }
    }
}

private struct LedgerlyTabBar: View {
    @Binding var selection: RootTab

    var body: some View {
        HStack(spacing: 2) {
            ForEach(RootTab.allCases) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol).font(.system(size: 21, weight: .semibold))
                        Text(tab.title).font(.system(size: 14, weight: selection == tab ? .bold : .semibold))
                    }
                    .foregroundStyle(selection == tab ? Color(red: 0.62, green: 0.72, blue: 1.0) : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selection == tab ? Color.white.opacity(0.09) : .clear, in: .rect(cornerRadius: 16))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.35) }
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
                        Text("Your accounts")
                            .font(.title3.bold())
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
                                            .font(.subheadline)
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
            .navigationBarTitleDisplayMode(.large)
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
                        Text("Your money at a glance")
                            .font(.title3.bold())
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
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func insightCard(_ title: String, value: Int, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
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
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedTransaction.bookedAt, order: .reverse) private var transactions: [CachedTransaction]
    @Query(sort: \RecurringPayment.nextDate) private var recurringPayments: [RecurringPayment]
    @State private var showingNewRecurringPayment = false

    var body: some View {
        NavigationStack {
            ZStack {
                LedgerlyBackground()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Recurring payments").font(.title2.bold())
                            Spacer()
                            Button { showingNewRecurringPayment = true } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .font(.body.weight(.semibold))
                        }
                        .padding(.top, 10)

                        if recurringPayments.isEmpty {
                            Button { showingNewRecurringPayment = true } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "calendar.badge.plus")
                                        .font(.title2)
                                        .foregroundStyle(.blue)
                                        .frame(width: 48, height: 48)
                                        .background(.blue.opacity(0.12), in: .rect(cornerRadius: 15))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Plan your regular bills").font(.headline)
                                        Text("Add rent, subscriptions, or any repeating payment.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 4)
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .ledgerlyGlass(cornerRadius: 20)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ForEach(recurringPayments) { payment in
                                recurringRow(payment)
                                    .contextMenu {
                                        Button("Delete", systemImage: "trash", role: .destructive) { context.delete(payment); try? context.save() }
                                    }
                            }
                        }

                        Text("Transactions")
                            .font(.title2.bold())
                            .padding(.top, 18)

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
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(money(transaction.amountMinor, transaction.currency))
                                            .foregroundStyle(transaction.amountMinor > 0 ? .blue : .primary)
                                        if transaction.pending {
                                            Text("Pending").font(.footnote).foregroundStyle(.orange)
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
                                description: Text("Transactions you add or sync will appear here.")
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
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showingNewRecurringPayment) { NewRecurringPaymentView() }
        }
    }

    private func recurringRow(_ payment: RecurringPayment) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "repeat")
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 46, height: 46)
                .background(.blue.opacity(0.12), in: .rect(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(payment.name).font(.headline)
                Text("\(payment.frequencyLabel) · next \(payment.nextDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(money(-payment.amountMinor, payment.currency)).font(.body.weight(.semibold))
        }
        .padding(16)
        .ledgerlyGlass(cornerRadius: 20)
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
                Section { Text("This account is saved locally. You can enable sync later in Settings.").font(.subheadline).foregroundStyle(.secondary) }
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
        let account = CachedAccount(name: name.trimmingCharacters(in: .whitespaces), institution: institution.trimmingCharacters(in: .whitespaces).isEmpty ? "Manual" : institution.trimmingCharacters(in: .whitespaces), kind: kind, amountMinor: minor, currency: currency.uppercased())
        context.insert(account)
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        dismiss()
    }
}

private struct NewRecurringPaymentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var name = ""
    @State private var amount = ""
    @State private var currency = "USD"
    @State private var frequency = "monthly"
    @State private var nextDate = Date()
    @State private var accountId = ""
    @State private var category = "Bills"
    private let frequencies = [("weekly", "Weekly"), ("everyTwoWeeks", "Every 2 weeks"), ("monthly", "Monthly"), ("yearly", "Yearly")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment") {
                    TextField("Name", text: $name)
                        .font(.body)
                    TextField("Amount", text: $amount)
                        .font(.body)
                        .keyboardType(.decimalPad)
                    TextField("Currency", text: $currency)
                        .font(.body)
                        .textInputAutocapitalization(.characters)
                    TextField("Category", text: $category)
                        .font(.body)
                }
                Section("Schedule") {
                    Picker("Repeats", selection: $frequency) {
                        ForEach(frequencies, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    DatePicker("Next payment", selection: $nextDate, displayedComponents: .date)
                }
                if !accounts.isEmpty {
                    Section("Account") {
                        Picker("Pay from", selection: $accountId) {
                            Text("Not selected").tag("")
                            ForEach(accounts) { Text($0.name).tag($0.id) }
                        }
                    }
                }
                Section {
                    Text("Ledgerly will track this schedule. It will not move money or charge the account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New recurring payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount <= 0) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save() {
        context.insert(RecurringPayment(
            name: name.trimmingCharacters(in: .whitespaces),
            amountMinor: parsedAmount,
            currency: currency.uppercased(),
            frequency: frequency,
            nextDate: nextDate,
            accountId: accountId.isEmpty ? nil : accountId,
            category: category.trimmingCharacters(in: .whitespaces).isEmpty ? "Bills" : category.trimmingCharacters(in: .whitespaces)
        ))
        try? context.save()
        dismiss()
    }
}

private func money(_ amount: Int, _ currency: String) -> String {
    (Double(amount) / 100).formatted(.currency(code: currency))
}
