import SwiftData
import SwiftUI
import Observation

@main
struct LedgerlyApp: App {
    @State private var session = SessionController()
    @State private var security = AppSecurityController()
    @State private var screenshots = ScreenshotNotificationController()
    var body: some Scene {
        WindowGroup {
            LedgerlyPrivacyRoot {
                if session.canUseApp { RootTabView().environment(session) }
                else { LoginView().environment(session) }
            }
            .environment(security)
            .environment(screenshots)
        }
            .modelContainer(for: [CachedAccount.self, CachedTransaction.self, SyncSetting.self, PendingMutation.self, PendingAccountMutation.self, PendingTransactionCreate.self, PendingRecurringMutation.self, PendingStockMutation.self, RecurringPayment.self, StockHolding.self, StockTrade.self])
    }
}

@MainActor @Observable final class SessionController {
    var isAuthenticated = KeychainStore().token() != nil
    var localOnly = UserDefaults.standard.bool(forKey: "ledgerly.localOnly")
    var canUseApp: Bool { isAuthenticated || localOnly }
    func complete(_ response: AuthResponse, apiURL: URL, convexURL: URL) {
        KeychainStore().saveToken(response.token)
        // Keep the addresses that this device successfully used. The API's
        // advertised URL can be an internal Docker/localhost address that is
        // not reachable from an iPhone.
        UserDefaults.standard.set(apiURL.absoluteString, forKey: "ledgerly.apiURL")
        UserDefaults.standard.set(convexURL.absoluteString, forKey: "ledgerly.convexURL")
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
    @State private var apiURL = AppConfig.baseURL.absoluteString
    @State private var convexURL = AppConfig.convexURL.absoluteString
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
            session.complete(response, apiURL: api, convexURL: convex)
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
            if UserDefaults.standard.string(forKey: "ledgerly.convexURL") == nil { convexURL = config.convexUrl }
        }
    }
}

private struct RootTabView: View {
    private enum RootTab: Hashable { case overview, accounts, add, activity, settings }
    private enum AddFlow: String, Identifiable { case bill, recurring, moneyIn, moneyOut; var id: String { rawValue } }
    @State private var selection = RootTab.overview
    @State private var previousSelection = RootTab.overview
    @State private var addFlow: AddFlow?

    var body: some View {
        TabView(selection: $selection) {
            Tab("Insights", systemImage: AppIcon.insights, value: RootTab.overview) {
                DashboardView()
            }

            Tab("Accounts", systemImage: AppIcon.accounts, value: RootTab.accounts) {
                NativeAccountsView()
            }

            Tab(value: RootTab.add) {
                Color.clear
            } label: {
                EmptyView()
            }

            Tab("Activity", systemImage: AppIcon.activity, value: RootTab.activity) {
                NativeActivityView()
            }

            Tab("Settings", systemImage: AppIcon.settings, value: RootTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(.blue)
        .onChange(of: selection) { oldValue, newValue in
            if newValue == .add {
                selection = oldValue == .add ? previousSelection : oldValue
            } else {
                previousSelection = newValue
            }
        }
        .overlay(alignment: .bottom) {
            Menu {
                Button("Add money", systemImage: "plus.circle.fill") { addFlow = .moneyIn }
                Button("Spend money", systemImage: "minus.circle.fill") { addFlow = .moneyOut }
                Divider()
                Button("One-time bill", systemImage: "doc.badge.plus") { addFlow = .bill }
                Button("Recurring bill", systemImage: "repeat") { addFlow = .recurring }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 23, weight: .semibold))
                    Text("Add")
                        .font(.caption2)
                }
                .frame(width: 74, height: 50)
                .contentShape(Rectangle())
            }
            .tint(.blue)
            .accessibilityLabel("Add")
            .accessibilityHint("Opens quick actions")
            .padding(.bottom, 1)
        }
        .sheet(item: $addFlow) { flow in
            switch flow {
            case .bill: NewBillView()
            case .recurring: NewRecurringPaymentView()
            case .moneyIn: QuickAccountEntryPicker(direction: .moneyIn)
            case .moneyOut: QuickAccountEntryPicker(direction: .moneyOut)
            }
        }
        .task { openPendingAddFlow() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            openPendingAddFlow()
        }
    }

    private func openPendingAddFlow() {
        guard UserDefaults.standard.string(forKey: "ledgerly.pendingAddFlow") == "moneyIn" else { return }
        UserDefaults.standard.removeObject(forKey: "ledgerly.pendingAddFlow")
        addFlow = .moneyIn
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
    private let kinds = [("checking", "Checking"), ("savings", "Savings"), ("credit", "Credit card"), ("sharedCredit", "Someone else's card"), ("investment", "Investment"), ("cash", "Cash")]

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
                if kind == "sharedCredit" {
                    Section {
                        Text("Use this for a parent’s or someone else’s card. It stays visible in Overview but is excluded from your own net worth.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
    private let existingPayment: RecurringPayment?
    private let transactionID: String?
    private let onSave: ((RecurringPayment) -> Void)?
    private let frequencies = [("weekly", "Weekly"), ("everyTwoWeeks", "Every 2 weeks"), ("monthly", "Monthly"), ("yearly", "Yearly")]

    init(payment: RecurringPayment? = nil) {
        existingPayment = payment
        transactionID = nil
        onSave = nil
        if let payment {
            _name = State(initialValue: payment.name)
            _amount = State(initialValue: NSDecimalNumber(value: Double(payment.amountMinor) / 100).stringValue)
            _currency = State(initialValue: payment.currency)
            _frequency = State(initialValue: payment.frequency)
            _nextDate = State(initialValue: payment.nextDate)
            _accountId = State(initialValue: payment.accountId ?? "")
            _category = State(initialValue: payment.category)
        }
    }

    init(transaction: TransactionSnapshot, onSave: ((RecurringPayment) -> Void)? = nil) {
        existingPayment = nil
        transactionID = transaction.id
        self.onSave = onSave
        let purchaseAmount = transaction.originalAmountMinor ?? transaction.amountMinor
        _name = State(initialValue: transaction.title)
        _amount = State(initialValue: NSDecimalNumber(value: Double(abs(purchaseAmount)) / 100).stringValue)
        _currency = State(initialValue: transaction.originalCurrency ?? transaction.currency)
        _nextDate = State(initialValue: Calendar.current.date(byAdding: .month, value: 1, to: transaction.bookedDate ?? Date()) ?? Date())
        _accountId = State(initialValue: transaction.accountID)
        _category = State(initialValue: transaction.category ?? "Bills")
    }

    private var availableAccounts: [CachedAccount] { accounts }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill") {
                    TextField("Name", text: $name)
                        .font(.body)
                    MoneyEntryRow(label: "Amount", amount: $amount, currency: $currency)
                    TransactionCategoryPicker(selection: $category)
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
                            ForEach(availableAccounts) { Text("\($0.name) · \($0.currency)").tag($0.id) }
                        }
                        Text("The bank may settle this bill in the account's currency. The bill keeps its original currency.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("This bill repeats automatically in Ledgerly. It does not move money or charge the account.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existingPayment == nil ? "Add recurring bill" : "Edit recurring bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount <= 0) }
            }
            .task { selectDefaultAccount() }
        }
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save() {
        let bill = existingPayment ?? RecurringPayment(
            name: name, amountMinor: parsedAmount, currency: currency, frequency: frequency,
            nextDate: nextDate, accountId: nil, category: category
        )
        bill.name = name.trimmingCharacters(in: .whitespaces)
        bill.amountMinor = parsedAmount
        bill.currency = currency
        bill.frequency = frequency
        bill.nextDate = nextDate
        bill.accountId = accountId.isEmpty ? nil : accountId
        bill.category = category.trimmingCharacters(in: .whitespaces).isEmpty ? "Bills" : category.trimmingCharacters(in: .whitespaces)
        if existingPayment == nil { context.insert(bill) }
        context.insert(PendingRecurringMutation(entityId: bill.id, action: "upsert"))
        let transactions = (try? context.fetch(FetchDescriptor<CachedTransaction>())) ?? []
        if let transactionID, let transaction = transactions.first(where: { $0.id == transactionID }) {
            transaction.recurringPaymentId = bill.id
            transaction.updatedAt = ISO8601DateFormatter().string(from: Date())
            enqueueFullTransaction(context: context, transactionID: transaction.id)
        }
        for transaction in transactions where transaction.recurringPaymentId == nil {
            autoLinkRecurringPayment(transaction, payments: [bill], context: context)
        }
        try? context.save()
        onSave?(bill)
        dismiss()
    }

    private func selectDefaultAccount() {
        if availableAccounts.contains(where: { $0.id == accountId }) { return }
        accountId = availableAccounts.first(where: { $0.currency == currency })?.id ?? availableAccounts.first?.id ?? ""
    }
}
