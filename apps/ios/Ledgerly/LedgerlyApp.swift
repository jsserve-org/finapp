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
            .modelContainer(for: [CachedAccount.self, CachedTransaction.self, SyncSetting.self, PendingMutation.self, PendingAccountMutation.self, PendingTransactionCreate.self, PendingRecurringMutation.self, RecurringPayment.self])
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
        NavigationStack {
            Form {
                Section {
                    Text(registration ? "Create credentials for your self-hosted server." : "Start locally, or sign in to sync across devices.")
                        .foregroundStyle(.secondary)
                    if !registration {
                        Button { session.continueLocally() } label: {
                            Label("Continue on this iPhone", systemImage: "iphone")
                        }
                    }
                }
                Section("Server") {
                        TextField("API endpoint", text: $apiURL).textContentType(.URL).textInputAutocapitalization(.never).keyboardType(.URL)
                        TextField("Convex endpoint", text: $convexURL).textContentType(.URL).textInputAutocapitalization(.never).keyboardType(.URL)
                }
                Section("Account") {
                        TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never)
                        SecureField("Password (10+ characters)", text: $password).textContentType(registration ? .newPassword : .password)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button { Task { await submit() } } label: {
                        if working { ProgressView() } else { Text(registration ? "Create account" : "Log in") }
                    }.disabled(working || username.count < 3 || password.count < 10)
                    if registration || registrationEnabled {
                        Button(registration ? "Already have an account? Log in" : "Need an account? Register") { registration.toggle(); error = nil }
                    }
                }
            }
            .navigationTitle(registration ? "Create account" : "Ledgerly")
        }
        .task { await loadServerConfig() }
    }

    private func submit() async {
        guard let api = URL(string: apiURL), let convex = URL(string: convexURL), ["http", "https"].contains(api.scheme), ["http", "https"].contains(convex.scheme) else { error = "Enter valid HTTP(S) endpoint URLs."; return }
        working = true; error = nil
        UserDefaults.standard.set(api.absoluteString, forKey: "ledgerly.apiURL")
        do {
            let response = try await APIClient.shared.authenticate(username: username, password: password, convexURL: convex, register: registration)
            session.complete(response)
        } catch APIError.http(let status, let message) {
            error = message ?? (status == 401 ? "Invalid username or password." : "Server rejected the request (\(status)).")
        }
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
    var body: some View {
        TabView {
            Tab("Overview", systemImage: AppIcon.overview) {
                DashboardView()
            }

            Tab("Accounts", systemImage: AppIcon.accounts) {
                NativeAccountsView()
            }

            Tab("Insights", systemImage: AppIcon.insights) {
                NativeInsightsView()
            }

            Tab("Activity", systemImage: AppIcon.activity) {
                NativeActivityView()
            }

            Tab("Settings", systemImage: AppIcon.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(.blue)
    }
}

struct NewAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var institution = ""
    @State private var kind = "checking"
    @State private var balance = ""
    @State private var currency = SupportedCurrency.defaultCode
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
                    Picker("Currency", selection: $currency) {
                        ForEach(SupportedCurrency.all) { option in
                            Text("\(option.code) — \(option.name)").tag(option.code)
                        }
                    }
                }
                Section { Text("This account is saved locally. You can enable sync later in Settings.").font(.subheadline).foregroundStyle(.secondary) }
            }
            .navigationTitle("New account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }

    private func save() {
        let decimal = Decimal(string: balance.replacingOccurrences(of: ",", with: ".")) ?? 0
        let minor = NSDecimalNumber(decimal: decimal * 100).intValue
        let account = CachedAccount(name: name.trimmingCharacters(in: .whitespaces), institution: institution.trimmingCharacters(in: .whitespaces).isEmpty ? "Manual" : institution.trimmingCharacters(in: .whitespaces), kind: kind, amountMinor: minor, currency: currency)
        context.insert(account)
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        dismiss()
    }
}

struct NewRecurringPaymentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var name = ""
    @State private var amount = ""
    @State private var currency = SupportedCurrency.defaultCode
    @State private var frequency = "monthly"
    @State private var nextDate = Date()
    @State private var accountId = ""
    @State private var category = "Bills"
    private let frequencies = [("weekly", "Weekly"), ("everyTwoWeeks", "Every 2 weeks"), ("monthly", "Monthly"), ("yearly", "Yearly")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Name", text: $name)
                        .font(.body)
                    TextField("Amount", text: $amount)
                        .font(.body)
                        .keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(SupportedCurrency.all) { option in
                            Text("\(option.code) — \(option.name)").tag(option.code)
                        }
                    }
                    TextField("Category", text: $category)
                        .font(.body)
                }
                Section("Repeats") {
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
                    Text("This bill repeats automatically in Ledgerly. It does not move money or charge the account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add recurring bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount <= 0) }
            }
        }
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save() {
        let bill = RecurringPayment(
            name: name.trimmingCharacters(in: .whitespaces),
            amountMinor: parsedAmount,
            currency: currency,
            frequency: frequency,
            nextDate: nextDate,
            accountId: accountId.isEmpty ? nil : accountId,
            category: category.trimmingCharacters(in: .whitespaces).isEmpty ? "Bills" : category.trimmingCharacters(in: .whitespaces)
        )
        context.insert(bill)
        context.insert(PendingRecurringMutation(entityId: bill.id, action: "upsert"))
        try? context.save()
        dismiss()
    }
}
